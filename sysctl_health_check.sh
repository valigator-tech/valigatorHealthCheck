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

# Function to check if swap is disabled
check_swap_disabled() {
  echo -e "\n${YELLOW}=== Memory Management ===${NC}"
  echo -e "${BLUE}Checking swap status...${NC}"
  
  # Get swap information using swapon command
  if command -v swapon &> /dev/null; then
    swap_info=$(swapon --show 2>/dev/null)
    if [ -z "$swap_info" ]; then
      swap_status="disabled"
    else
      swap_status="enabled"
    fi
  else
    # Alternative method using /proc/swaps
    if [ -f "/proc/swaps" ]; then
      swap_count=$(grep -v "^Filename" /proc/swaps | wc -l)
      if [ "$swap_count" -eq 0 ]; then
        swap_status="disabled"
      else
        swap_status="enabled"
      fi
    else
      echo -e "  ${RED}FAIL: Unable to determine swap status${NC}"
      return 1
    fi
  fi
  
  # Check swap status
  if [ "$swap_status" = "disabled" ]; then
    echo -e "  ${GREEN}PASS: Swap is disabled${NC}"
    return 0
  else
    echo -e "  ${RED}FAIL: Swap is enabled${NC}"
    echo -e "  Current status: Swap is ${RED}$swap_status${NC}"
    echo -e "  Expected: Swap should be ${GREEN}disabled${NC}"
    return 1
  fi
}

# Check fail2ban service
if ! check_fail2ban; then
  ((failures++))
fi

# Function to check if CPU boost is enabled
check_cpu_boost() {
  echo -e "\n${YELLOW}=== CPU Performance ===${NC}"
  echo -e "${BLUE}Checking CPU boost status...${NC}"
  
  local boost_path="/sys/devices/system/cpu/cpufreq/boost"
  local intel_boost_path="/sys/devices/system/cpu/intel_pstate/no_turbo"
  local amd_boost_path="/sys/devices/system/cpu/cpufreq/boost"
  local boost_status=""
  
  # Check if any of the boost control files exist
  if [ -f "$boost_path" ]; then
    boost_value=$(cat "$boost_path")
    if [ "$boost_value" -eq 1 ]; then
      boost_status="enabled"
    else
      boost_status="disabled"
    fi
  elif [ -f "$intel_boost_path" ]; then
    turbo_value=$(cat "$intel_boost_path")
    if [ "$turbo_value" -eq 0 ]; then
      boost_status="enabled"  # Intel: no_turbo=0 means boost is enabled
    else
      boost_status="disabled"
    fi
  elif [ -f "$amd_boost_path" ]; then
    boost_value=$(cat "$amd_boost_path")
    if [ "$boost_value" -eq 1 ]; then
      boost_status="enabled"
    else
      boost_status="disabled"
    fi
  else
    # Check individual CPU boosting
    boost_files_found=false
    all_boost_enabled=true
    
    for cpu_dir in /sys/devices/system/cpu/cpu*/cpufreq; do
      boost_file="$cpu_dir/scaling_boost_freq"
      
      if [ -f "$boost_file" ]; then
        boost_files_found=true
        boost_freq=$(cat "$boost_file")
        
        if [ "$boost_freq" -eq 0 ]; then
          all_boost_enabled=false
          break
        fi
      fi
    done
    
    if [ "$boost_files_found" = true ]; then
      if [ "$all_boost_enabled" = true ]; then
        boost_status="enabled"
      else
        boost_status="disabled"
      fi
    else
      echo -e "  ${YELLOW}WARNING: Could not determine CPU boost status${NC}"
      echo -e "  ${YELLOW}This might be due to the system not supporting CPU boost or using a different method${NC}"
      return 0  # Don't count as failure since we can't determine for sure
    fi
  fi
  
  # Check boost status
  if [ "$boost_status" = "enabled" ]; then
    echo -e "  ${GREEN}PASS: CPU boost is enabled${NC}"
    return 0
  elif [ "$boost_status" = "disabled" ]; then
    echo -e "  ${RED}FAIL: CPU boost is disabled${NC}"
    echo -e "  Expected: ${GREEN}enabled${NC}"
    return 1
  fi
}

# Check swap status
if ! check_swap_disabled; then
  ((failures++))
fi

# Function to check for package updates
check_package_updates() {
  echo -e "\n${YELLOW}=== System Updates ===${NC}"
  echo -e "${BLUE}Checking pending package updates...${NC}"
  
  local max_allowed_updates=5
  local update_count=0
  local pkgmanager=""
  
  # Detect package manager
  if command -v apt &> /dev/null; then
    pkgmanager="apt"
    # Ensure package lists are up-to-date but don't update packages
    apt-get update -qq &> /dev/null
    update_count=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." | wc -l)
  elif command -v dnf &> /dev/null; then
    pkgmanager="dnf"
    update_count=$(dnf check-update --quiet 2>/dev/null | grep -v "^$" | wc -l)
  elif command -v yum &> /dev/null; then
    pkgmanager="yum"
    update_count=$(yum check-update --quiet 2>/dev/null | grep -v "^$" | wc -l)
  elif command -v pacman &> /dev/null; then
    pkgmanager="pacman"
    # Update package database first
    pacman -Sy &>/dev/null
    update_count=$(pacman -Qu | wc -l)
  elif command -v zypper &> /dev/null; then
    pkgmanager="zypper"
    update_count=$(zypper list-updates 2>/dev/null | grep "|" | grep -v "^+-" | wc -l)
  else
    echo -e "  ${YELLOW}WARNING: Could not determine package manager${NC}"
    return 0  # Don't count as failure since we can't determine
  fi
  
  # Check if update count is acceptable
  if [ "$update_count" -le "$max_allowed_updates" ]; then
    echo -e "  ${GREEN}PASS: $update_count package update(s) pending ($pkgmanager)${NC}"
    echo -e "  Maximum allowed: $max_allowed_updates"
    return 0
  else
    echo -e "  ${RED}FAIL: $update_count package update(s) pending ($pkgmanager)${NC}"
    echo -e "  Maximum allowed: ${GREEN}$max_allowed_updates${NC}"
    return 1
  fi
}

# Check CPU boost status
if ! check_cpu_boost; then
  ((failures++))
fi

# Check package updates
if ! check_package_updates; then
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