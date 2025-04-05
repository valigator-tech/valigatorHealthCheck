#!/bin/bash

# We don't want to exit immediately on error since we want to run all checks

# Define colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Organize checks by category
declare -A check_categories=(
  ["TCP Buffer Sizes"]="net.ipv4.tcp_rmem net.ipv4.tcp_wmem"
  ["TCP Optimization"]="net.ipv4.tcp_congestion_control net.ipv4.tcp_fastopen net.ipv4.tcp_timestamps net.ipv4.tcp_sack net.ipv4.tcp_low_latency net.ipv4.tcp_tw_reuse net.ipv4.tcp_no_metrics_save net.ipv4.tcp_moderate_rcvbuf"
  ["Kernel Optimization"]="kernel.timer_migration kernel.hung_task_timeout_secs kernel.pid_max"
  ["Virtual Memory Tuning"]="vm.swappiness vm.max_map_count vm.stat_interval vm.dirty_ratio vm.dirty_background_ratio vm.min_free_kbytes vm.dirty_expire_centisecs vm.dirty_writeback_centisecs vm.dirtytime_expire_seconds"
  ["Solana Specific Tuning"]="net.core.rmem_max net.core.rmem_default net.core.wmem_max net.core.wmem_default"
  # Add more categories here in the future
)

# Array of sysctl checks in format: "parameter expected_value"
declare -A checks=(
  ["net.ipv4.tcp_rmem"]="10240 87380 12582912"
  ["net.ipv4.tcp_wmem"]="10240 87380 12582912"
  ["net.ipv4.tcp_congestion_control"]="westwood"
  ["net.ipv4.tcp_fastopen"]="3"
  ["net.ipv4.tcp_timestamps"]="0"
  ["net.ipv4.tcp_sack"]="1"
  ["net.ipv4.tcp_low_latency"]="1"
  ["net.ipv4.tcp_tw_reuse"]="1"
  ["net.ipv4.tcp_no_metrics_save"]="1"
  ["net.ipv4.tcp_moderate_rcvbuf"]="1"
  ["kernel.timer_migration"]="0"
  ["kernel.hung_task_timeout_secs"]="30"
  ["kernel.pid_max"]="49152"
  ["vm.swappiness"]="30"
  ["vm.max_map_count"]="2000000"
  ["vm.stat_interval"]="10"
  ["vm.dirty_ratio"]="40"
  ["vm.dirty_background_ratio"]="10"
  ["vm.min_free_kbytes"]="3000000"
  ["vm.dirty_expire_centisecs"]="36000"
  ["vm.dirty_writeback_centisecs"]="3000"
  ["vm.dirtytime_expire_seconds"]="43200"
  ["net.core.rmem_max"]="134217728"
  ["net.core.rmem_default"]="134217728"
  ["net.core.wmem_max"]="134217728"
  ["net.core.wmem_default"]="134217728"
  # Add more checks here in the future
)

# Counter for failures
failures=0

# Function to normalize whitespace in a string
normalize_whitespace() {
  echo "$1" | tr -s '[:space:]' ' ' | xargs
}

# Function to check a single sysctl parameter
check_sysctl() {
  local param="$1"
  local expected="$2"
  local current
  local normalized_expected
  local normalized_current

  echo -e "${BLUE}Checking $param...${NC}"
  
  # Get the current value
  current=$(sysctl -n "$param" 2>/dev/null)
  
  # Check if sysctl command was successful
  if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Could not retrieve $param value. This may not be a Linux system or you don't have permission.${NC}"
    return 1
  fi
  
  # Special case for kernel.pid_max which should be equal to or greater than expected
  if [ "$param" = "kernel.pid_max" ]; then
    if [ "$current" -ge "$expected" ]; then
      echo -e "  ${GREEN}PASS: $param value is sufficient: $current (minimum required: $expected)${NC}"
      return 0
    else
      echo -e "  ${RED}FAIL: $param value is too low.${NC}"
      echo -e "  Current value: ${YELLOW}$current${NC}"
      echo -e "  Minimum required: ${GREEN}$expected${NC}"
      return 1
    fi
  fi
  
  # For other parameters, normalize whitespace and check for exact match
  normalized_expected=$(normalize_whitespace "$expected")
  normalized_current=$(normalize_whitespace "$current")
  
  # Check if the normalized values match
  if [ "$normalized_current" != "$normalized_expected" ]; then
    echo -e "  ${RED}FAIL: $param value is incorrect.${NC}"
    echo -e "  Current value: ${YELLOW}$current${NC}"
    echo -e "  Expected value: ${GREEN}$expected${NC}"
    return 1
  else
    echo -e "  ${GREEN}PASS: $param value is correct: $current${NC}"
    return 0
  fi
}

# Function to check CPU governor mode
check_cpu_governor() {
  local expected="performance"
  local mismatched_cpus=()
  local total_cpus=0
  local mismatched=0

  echo -e "\n${YELLOW}=== CPU Governor Settings ===${NC}"
  echo -e "${BLUE}Checking CPU governor mode...${NC}"
  
  # Check if the cpu frequency scaling directory exists
  if [ ! -d "/sys/devices/system/cpu/cpu0/cpufreq" ]; then
    echo -e "  ${RED}FAIL: CPU frequency scaling is not available on this system.${NC}"
    return 1
  fi
  
  # Check governor for each CPU
  for cpu_dir in /sys/devices/system/cpu/cpu*/cpufreq; do
    if [ -f "$cpu_dir/scaling_governor" ]; then
      cpu_num=$(echo "$cpu_dir" | grep -o 'cpu[0-9]*' | sed 's/cpu//')
      current=$(cat "$cpu_dir/scaling_governor")
      
      ((total_cpus++))
      
      if [ "$current" != "$expected" ]; then
        mismatched_cpus+=("$cpu_num:$current")
        ((mismatched++))
      fi
    fi
  done
  
  # Display a single summary line
  if [ $mismatched -eq 0 ]; then
    echo -e "  ${GREEN}PASS: All $total_cpus CPU cores are set to '$expected' governor${NC}"
    return 0
  else
    echo -e "  ${RED}FAIL: $mismatched of $total_cpus CPU cores are not using '$expected' governor${NC}"
    if [ $mismatched -le 4 ]; then
      # Show details only if there are few mismatched cores
      echo -ne "  Mismatched cores: "
      for info in "${mismatched_cpus[@]}"; do
        core=${info%%:*}
        gov=${info#*:}
        echo -ne "CPU $core=$gov "
      done
      echo ""
    fi
    echo -e "  Expected: ${GREEN}$expected${NC} for all cores"
    return 1
  fi
}

# Run all checks
echo -e "${BLUE}Starting system health checks...${NC}"

# Run sysctl checks by category
for category in "${!check_categories[@]}"; do
  echo -e "\n${YELLOW}=== $category ===${NC}"
  
  # Get all parameters in this category
  params=(${check_categories[$category]})
  
  # Run each check in this category
  for param in "${params[@]}"; do
    if ! check_sysctl "$param" "${checks[$param]}"; then
      ((failures++))
    fi
  done
done

# Function to check if fail2ban is enabled and running
check_fail2ban() {
  echo -e "\n${YELLOW}=== Security Services ===${NC}"
  echo -e "${BLUE}Checking fail2ban service...${NC}"
  
  # Check if systemctl command exists
  if ! command -v systemctl &> /dev/null; then
    echo -e "  ${RED}FAIL: systemctl command not found. Is this a systemd-based system?${NC}"
    return 1
  fi
  
  # Check if fail2ban service exists
  if ! systemctl list-unit-files | grep -q fail2ban; then
    echo -e "  ${RED}FAIL: fail2ban service is not installed${NC}"
    return 1
  fi
  
  # Check if fail2ban is enabled
  if systemctl is-enabled fail2ban &> /dev/null; then
    enabled_status="${GREEN}enabled${NC}"
  else
    enabled_status="${RED}disabled${NC}"
    enabled_ok=false
  fi
  
  # Check if fail2ban is running
  if systemctl is-active fail2ban &> /dev/null; then
    active_status="${GREEN}running${NC}"
  else
    active_status="${RED}stopped${NC}"
    active_ok=false
  fi
  
  # Display status
  if [ "$enabled_status" = "${GREEN}enabled${NC}" ] && [ "$active_status" = "${GREEN}running${NC}" ]; then
    echo -e "  ${GREEN}PASS: fail2ban service is enabled and running${NC}"
    return 0
  else
    echo -e "  ${RED}FAIL: fail2ban service status issue${NC}"
    echo -e "  Service status: $active_status, boot status: $enabled_status"
    echo -e "  Expected: ${GREEN}running${NC} and ${GREEN}enabled${NC}"
    return 1
  fi
}

# Check CPU governor
if ! check_cpu_governor; then
  ((failures++))
fi

# Check fail2ban service
if ! check_fail2ban; then
  ((failures++))
fi

# Summary
echo ""
echo -e "${BLUE}Health check complete.${NC}"
if [ $failures -eq 0 ]; then
  echo -e "${GREEN}All checks passed successfully.${NC}"
  exit 0
else
  echo -e "${RED}$failures check(s) failed.${NC}"
  exit 1
fi