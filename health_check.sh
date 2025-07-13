#!/bin/bash

# We don't want to exit immediately on error since we want to run all checks

# Define colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m' # Changed to cyan (lighter blue)
NC='\033[0m' # No Color

# Parse command line arguments
QUIET_MODE=false
CONFIG_FILE="./config.json"

# Parse command line options
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -q|--quiet)
      QUIET_MODE=true
      shift
      ;;
    -c|--config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo "Options:"
      echo "  -q, --quiet             Suppress detailed output, only show final summary"
      echo "  -c, --config FILE       Use specified config file (default: ./config.json)"
      echo "  -h, --help              Display this help message and exit"
      echo ""
      echo "Note: Use the config.json file to enable/disable specific checks"
      exit 0
      ;;
    *)
      echo "Unknown option: $key"
      echo "Use --help to see available options"
      exit 1
      ;;
  esac
done

# Check if the config file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo -e "${RED}Error: Config file not found: $CONFIG_FILE${NC}"
  echo "Please specify a valid config file with --config option or create the default config.json"
  exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo -e "${RED}Error: jq is not installed. Please install jq to parse the config file.${NC}"
  echo "On Debian/Ubuntu: sudo apt-get install jq"
  echo "On CentOS/RHEL: sudo yum install jq"
  echo "On Fedora: sudo dnf install jq"
  exit 1
fi

# If quiet mode is enabled, redirect all output to /dev/null
# But save the original stdout first to restore it for the summary
if [ "$QUIET_MODE" = true ]; then
  exec 3>&1
  exec 1>/dev/null 2>/dev/null
fi

# Load default configuration values
load_defaults() {
  # Initialize with default categories
  check_categories["TCP Buffer Sizes"]="net.ipv4.tcp_rmem net.ipv4.tcp_wmem"
  check_categories["TCP Optimization"]="net.ipv4.tcp_congestion_control net.ipv4.tcp_fastopen net.ipv4.tcp_timestamps net.ipv4.tcp_sack net.ipv4.tcp_low_latency net.ipv4.tcp_tw_reuse net.ipv4.tcp_no_metrics_save net.ipv4.tcp_moderate_rcvbuf"
  check_categories["Kernel Optimization"]="kernel.timer_migration kernel.hung_task_timeout_secs kernel.pid_max"
  check_categories["Virtual Memory Tuning"]="vm.swappiness vm.max_map_count vm.stat_interval vm.dirty_ratio vm.dirty_background_ratio vm.min_free_kbytes vm.dirty_expire_centisecs vm.dirty_writeback_centisecs vm.dirtytime_expire_seconds"
  check_categories["Solana Specific Tuning"]="net.core.rmem_max net.core.rmem_default net.core.wmem_max net.core.wmem_default"
  
  # Initialize with default values
  checks["net.ipv4.tcp_rmem"]="10240 87380 12582912"
  checks["net.ipv4.tcp_wmem"]="10240 87380 12582912"
  checks["net.ipv4.tcp_congestion_control"]="westwood"
  checks["net.ipv4.tcp_fastopen"]="3"
  checks["net.ipv4.tcp_timestamps"]="0"
  checks["net.ipv4.tcp_sack"]="1"
  checks["net.ipv4.tcp_low_latency"]="1"
  checks["net.ipv4.tcp_tw_reuse"]="1"
  checks["net.ipv4.tcp_no_metrics_save"]="1"
  checks["net.ipv4.tcp_moderate_rcvbuf"]="1"
  checks["kernel.timer_migration"]="0"
  checks["kernel.hung_task_timeout_secs"]="30"
  checks["kernel.pid_max"]="49152"
  checks["vm.swappiness"]="30"
  checks["vm.max_map_count"]="2000000"
  checks["vm.stat_interval"]="10"
  checks["vm.dirty_ratio"]="40"
  checks["vm.dirty_background_ratio"]="10"
  checks["vm.min_free_kbytes"]="3000000"
  checks["vm.dirty_expire_centisecs"]="36000"
  checks["vm.dirty_writeback_centisecs"]="3000"
  checks["vm.dirtytime_expire_seconds"]="43200"
  checks["net.core.rmem_max"]="134217728"
  checks["net.core.rmem_default"]="134217728"
  checks["net.core.wmem_max"]="134217728"
  checks["net.core.wmem_default"]="134217728"
}

# Function to get a value from the config
get_config() {
  local key="$1"
  local default="$2"
  
  # Use grep to extract the specific config value to avoid jq errors
  local jq_result
  
  # Handle check enabling/disabling
  if [[ "$key" == .checksToRun.* ]]; then
    # Extract the last part of the key (after the last dot)
    local key_name=${key##*.}
    jq_result=$(grep -A20 '"checksToRun":' "$CONFIG_FILE" | grep "\"$key_name\":" | head -1 | sed 's/.*:[ ]*\([^",}]*\).*/\1/')
  elif [[ "$key" == .systemChecks.* ]]; then
    # Extract the last part of the key (after the last dot)
    local key_name=${key##*.}
    
    # Special case for nested objects
    case "$key" in
      .systemChecks.cpu.*)
        jq_result=$(grep -A10 '"cpu":' "$CONFIG_FILE" | grep "\"$key_name\":" | head -1 | sed 's/.*:[ ]*"\{0,1\}\([^",]*\)"\{0,1\}.*/\1/') ;;
      .systemChecks.security.*)
        jq_result=$(grep -A20 '"security":' "$CONFIG_FILE" | grep "\"$key_name\":" | head -1 | sed 's/.*:[ ]*"\{0,1\}\([^",]*\)"\{0,1\}.*/\1/') ;;
      .systemChecks.updates.*)
        jq_result=$(grep -A10 '"updates":' "$CONFIG_FILE" | grep "\"$key_name\":" | head -1 | sed 's/.*:[ ]*"\{0,1\}\([^",]*\)"\{0,1\}.*/\1/') ;;
      .systemChecks.memory.*)
        jq_result=$(grep -A10 '"memory":' "$CONFIG_FILE" | grep "\"$key_name\":" | head -1 | sed 's/.*:[ ]*"\{0,1\}\([^",]*\)"\{0,1\}.*/\1/') ;;
      .systemChecks.time.*)
        jq_result=$(grep -A10 '"time":' "$CONFIG_FILE" | grep "\"$key_name\":" | head -1 | sed 's/.*:[ ]*"\{0,1\}\([^",]*\)"\{0,1\}.*/\1/') ;;
      .systemChecks.logs.*)
        jq_result=$(grep -A10 '"logs":' "$CONFIG_FILE" | grep "\"$key_name\":" | head -1 | sed 's/.*:[ ]*"\{0,1\}\([^",]*\)"\{0,1\}.*/\1/') ;;
      *)
        jq_result="" ;;
    esac
  else
    jq_result=""
  fi
  
  # If the value is null or empty, use the default
  if [ -z "$jq_result" ]; then
    echo "$default"
  else
    # Clean up any trailing commas
    jq_result=$(echo "$jq_result" | sed 's/,$//')
    echo "$jq_result"
  fi
}

# Function to check if a specific check should be run
should_run_check() {
  local check_name="$1"
  local result=$(get_config ".checksToRun.$check_name" "true")
  
  # Convert to lowercase for standardization
  result=$(echo "$result" | tr '[:upper:]' '[:lower:]')
  
  if [ "$result" = "true" ] || [ "$result" = "yes" ] || [ "$result" = "1" ]; then
    return 0  # True - should run
  else
    return 1  # False - should not run
  fi
}

# Load configuration into check categories and checks
load_config() {
  echo -e "${BLUE}Loading configuration from: $CONFIG_FILE${NC}"
  
  # Clear existing check categories and checks
  declare -g -A check_categories=()
  declare -g -A checks=()
  
  # Check if the config file exists and is readable
  if [ ! -f "$CONFIG_FILE" ] || [ ! -r "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: Config file not found or not readable: $CONFIG_FILE${NC}"
    echo -e "${YELLOW}Falling back to default checks${NC}"
    load_defaults
    return
  fi
  
  # Check if it looks like a valid JSON file
  if ! grep -q "sysctlChecks" "$CONFIG_FILE"; then
    echo -e "${RED}Error: Invalid config file format (missing sysctlChecks)${NC}"
    echo -e "${YELLOW}Falling back to default checks${NC}"
    load_defaults
    return
  fi
  
  # Load defaults first, then override with config file values
  load_defaults
  
  # Using grep-based parsing instead of jq to avoid errors
  # Extract and process categories
  categories=$(grep -o '"[^"]*":' "$CONFIG_FILE" | grep -v "sysctlChecks\|systemChecks" | sed 's/"//g' | sed 's/://g')
  
  for category in $categories; do
    # Get the section for this category
    category_section=$(grep -A30 "\"$category\":" "$CONFIG_FILE" | grep -B30 -m1 "}," | grep -v "},")
    
    # Extract parameters for this category
    params=""
    while read -r line; do
      if [[ "$line" =~ \"([^\"]+)\" ]]; then
        param="${BASH_REMATCH[1]}"
        if [[ "$param" == net.* || "$param" == kernel.* || "$param" == vm.* ]]; then
          params="$params $param"
          
          # Extract the value
          if [[ "$line" =~ :\ *\"([^\"]*)\" ]]; then
            value="${BASH_REMATCH[1]}"
            checks["$param"]="$value"
          fi
        fi
      fi
    done <<< "$category_section"
    
    # Only add to check_categories if we found parameters
    if [ -n "$params" ]; then
      check_categories["$category"]="${params# }"  # Remove leading space
    fi
  done
}

# Define empty check arrays, which will be populated from config
declare -A check_categories
declare -A checks

# Load configuration from JSON file
load_config

# Counter for failures and array to track failed check names
failures=0
failed_checks=()

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
  
  # Special case for vm.swappiness which should be 30 or lower
  if [ "$param" = "vm.swappiness" ]; then
    if [ "$current" -le 30 ]; then
      echo -e "  ${GREEN}PASS: $param value is acceptable: $current (maximum allowed: 30)${NC}"
      return 0
    else
      echo -e "  ${RED}FAIL: $param value is too high.${NC}"
      echo -e "  Current value: ${YELLOW}$current${NC}"
      echo -e "  Maximum allowed: ${GREEN}30${NC}"
      return 1
    fi
  fi
  
  # Special case for tcp_congestion_control if set to bbr
  if [ "$param" = "net.ipv4.tcp_congestion_control" ] && [ "$current" = "bbr" ]; then
    echo -e "  ${YELLOW}WARNING: $param is set to BBR instead of westwood${NC}"
    echo -e "  Current value: ${YELLOW}$current${NC}"
    echo -e "  Expected value: ${GREEN}$expected${NC}"
    echo -e "  ${YELLOW}This is acceptable as BBR is also a good congestion control algorithm${NC}"
    return 0  # Return success since BBR is an acceptable alternative
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
  local expected=$(get_config '.systemChecks.cpu.governor' "performance")
  local mismatched_cpus=()
  local busy_cpus=()
  local total_cpus=0
  local mismatched=0
  local busy=0

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
      
      # Use 2>/dev/null to suppress the "Device or resource busy" error
      current=$(cat "$cpu_dir/scaling_governor" 2>/dev/null)
      
      # Check if we actually got a value
      if [ -z "$current" ]; then
        # Count busy CPUs separately
        busy_cpus+=("$cpu_num")
        ((busy++))
      else
        ((total_cpus++))
        
        if [ "$current" != "$expected" ]; then
          mismatched_cpus+=("$cpu_num:$current")
          ((mismatched++))
        fi
      fi
    fi
  done
  
  # Display a single summary line
  if [ $mismatched -eq 0 ] && [ $busy -eq 0 ]; then
    echo -e "  ${GREEN}PASS: All $total_cpus CPU cores are set to '$expected' governor${NC}"
    return 0
  elif [ $busy -gt 0 ] && [ $mismatched -eq 0 ]; then
    echo -e "  ${YELLOW}WARNING: $busy CPU cores couldn't be checked (device busy)${NC}"
    echo -e "  ${GREEN}PASS: All $total_cpus checkable CPU cores are set to '$expected' governor${NC}"
    if [ $busy -le 8 ]; then
      echo -ne "  Busy cores: "
      for core in "${busy_cpus[@]}"; do
        echo -ne "CPU $core "
      done
      echo ""
    fi
    return 0  # Consider this a pass if no mismatches and only busy errors
  else
    echo -e "  ${RED}FAIL: $mismatched of $total_cpus CPU cores are not using '$expected' governor${NC}"
    if [ $busy -gt 0 ]; then
      echo -e "  Note: $busy additional CPU cores couldn't be checked (device busy)"
    fi
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

# Run sysctl checks by category if enabled in config
if should_run_check "sysctlParams"; then
  for category in "${!check_categories[@]}"; do
    echo -e "\n${YELLOW}=== $category ===${NC}"
    
    # Get all parameters in this category
    params=(${check_categories[$category]})
    
    # Run each check in this category
    for param in "${params[@]}"; do
      if ! check_sysctl "$param" "${checks[$param]}"; then
        ((failures++))
        failed_checks+=("$category: $param")
      fi
    done
  done
else
  echo -e "\n${YELLOW}=== Sysctl Parameters ===${NC}"
  echo -e "${BLUE}Checking sysctl parameters... ${YELLOW}[SKIPPED]${NC}"
fi

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

# Check CPU governor if enabled in config
if should_run_check "cpuGovernor"; then
  if ! check_cpu_governor; then
    ((failures++))
    failed_checks+=("CPU Governor Settings")
  fi
else
  echo -e "\n${YELLOW}=== CPU Governor Settings ===${NC}"
  echo -e "${BLUE}Checking CPU governor mode... ${YELLOW}[SKIPPED]${NC}"
fi

# Function to check if swap is disabled
check_swap_disabled() {
  local swap_should_be_enabled=$(get_config '.systemChecks.memory.swapEnabled' "false")
  local expected_status
  
  if [ "$swap_should_be_enabled" = "true" ]; then
    expected_status="enabled"
  else
    expected_status="disabled"
  fi
  
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
  
  # Check swap status against expected value
  if [ "$swap_status" = "$expected_status" ]; then
    echo -e "  ${GREEN}PASS: Swap is $swap_status${NC}"
    return 0
  else
    echo -e "  ${RED}FAIL: Swap is $swap_status${NC}"
    echo -e "  Current status: Swap is ${RED}$swap_status${NC}"
    echo -e "  Expected: Swap should be ${GREEN}$expected_status${NC}"
    return 1
  fi
}

# Check fail2ban service if enabled in config
if should_run_check "fail2ban"; then
  if ! check_fail2ban; then
    ((failures++))
    failed_checks+=("Security Services: fail2ban")
  fi
else
  echo -e "\n${YELLOW}=== Security Services ===${NC}"
  echo -e "${BLUE}Checking fail2ban service... ${YELLOW}[SKIPPED]${NC}"
fi

# Function to check if CPU boost is enabled
check_cpu_boost() {
  local expected_status=$(get_config '.systemChecks.cpu.boost' "enabled")
  
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
  
  # Check boost status against configuration
  if [ "$boost_status" = "$expected_status" ]; then
    echo -e "  ${GREEN}PASS: CPU boost is $boost_status${NC}"
    return 0
  else
    echo -e "  ${RED}FAIL: CPU boost is $boost_status${NC}"
    echo -e "  Expected: ${GREEN}$expected_status${NC}"
    return 1
  fi
}

# Check swap status if enabled in config
if should_run_check "swapStatus"; then
  if ! check_swap_disabled; then
    ((failures++))
    failed_checks+=("Memory Management: Swap Status")
  fi
else
  echo -e "\n${YELLOW}=== Memory Management ===${NC}"
  echo -e "${BLUE}Checking swap status... ${YELLOW}[SKIPPED]${NC}"
fi

# Function to check for package updates
check_package_updates() {
  echo -e "\n${YELLOW}=== System Updates ===${NC}"
  echo -e "${BLUE}Checking pending package updates...${NC}"
  
  local max_allowed_updates=$(get_config '.systemChecks.updates.maxPendingUpdates' "5")
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

# Function to check if p-state driver is being used
check_pstate_driver() {
  local expected_driver=$(get_config '.systemChecks.cpu.driver' "pstate")
  
  echo -e "\n${YELLOW}=== CPU Driver ===${NC}"
  echo -e "${BLUE}Checking CPU scaling driver...${NC}"
  
  # Check if CPU frequency scaling is available
  if [ ! -d "/sys/devices/system/cpu/cpu0/cpufreq" ]; then
    echo -e "  ${RED}FAIL: CPU frequency scaling is not available on this system.${NC}"
    return 1
  fi
  
  # Get the current scaling driver
  driver_file="/sys/devices/system/cpu/cpu0/cpufreq/scaling_driver"
  if [ -f "$driver_file" ]; then
    driver=$(cat "$driver_file")
    
    # Check if the driver matches the expected one
    # Special case for pstate which can be intel_pstate or amd_pstate
    if [ "$expected_driver" = "pstate" ]; then
      if [[ "$driver" == *"pstate"* ]]; then
        echo -e "  ${GREEN}PASS: CPU is using p-state driver: $driver${NC}"
        return 0
      else
        echo -e "  ${RED}FAIL: CPU is not using p-state driver${NC}"
        echo -e "  Current driver: ${YELLOW}$driver${NC}"
        echo -e "  Expected: ${GREEN}intel_pstate or amd_pstate${NC}"
        return 1
      fi
    else
      # Direct driver name comparison
      if [ "$driver" = "$expected_driver" ]; then
        echo -e "  ${GREEN}PASS: CPU is using expected driver: $driver${NC}"
        return 0
      else
        echo -e "  ${RED}FAIL: CPU is not using expected driver${NC}"
        echo -e "  Current driver: ${YELLOW}$driver${NC}"
        echo -e "  Expected: ${GREEN}$expected_driver${NC}"
        return 1
      fi
    fi
  else
    echo -e "  ${RED}FAIL: Could not determine CPU scaling driver${NC}"
    return 1
  fi
}

# Check CPU boost status if enabled in config
if should_run_check "cpuBoost"; then
  if ! check_cpu_boost; then
    ((failures++))
    failed_checks+=("CPU Performance: Boost Status")
  fi
else
  echo -e "\n${YELLOW}=== CPU Performance ===${NC}"
  echo -e "${BLUE}Checking CPU boost status... ${YELLOW}[SKIPPED]${NC}"
fi

# Check CPU p-state driver if enabled in config
if should_run_check "cpuDriver"; then
  if ! check_pstate_driver; then
    ((failures++))
    failed_checks+=("CPU Driver: p-state")
  fi
else
  echo -e "\n${YELLOW}=== CPU Driver ===${NC}"
  echo -e "${BLUE}Checking CPU scaling driver... ${YELLOW}[SKIPPED]${NC}"
fi

# Function to check NTP synchronization status
check_ntp_sync() {
  echo -e "\n${YELLOW}=== Time Synchronization ===${NC}"
  echo -e "${BLUE}Checking NTP time sync status...${NC}"
  
  local ntp_synced=false
  local sync_method=""
  
  # Check for systemd-timesyncd
  if command -v timedatectl &> /dev/null; then
    if timedatectl status | grep -q "NTP service: active"; then
      ntp_synced=true
      sync_method="systemd-timesyncd"
    elif timedatectl status | grep -q "NTP enabled: yes"; then
      ntp_synced=true
      sync_method="systemd NTP"
    elif timedatectl status | grep -q "System clock synchronized: yes"; then
      ntp_synced=true
      sync_method="systemd (clock already synchronized)"
    fi
  fi
  
  # Check for chronyd if not already found
  if [ "$ntp_synced" = false ] && command -v chronyc &> /dev/null; then
    if chronyc tracking &> /dev/null; then
      sync_status=$(chronyc tracking | grep "Leap status" | cut -d ":" -f2 | xargs)
      if [ "$sync_status" = "Normal" ] || [ "$sync_status" = "Synchronized" ]; then
        ntp_synced=true
        sync_method="chrony"
      fi
    fi
  fi
  
  # Check for ntpd if not already found
  if [ "$ntp_synced" = false ] && command -v ntpq &> /dev/null; then
    if ntpq -p &> /dev/null && ntpq -c rv | grep -q "sync"; then
      ntp_synced=true
      sync_method="ntpd"
    fi
  fi
  
  # Check for OpenNTPD if not already found
  if [ "$ntp_synced" = false ] && command -v ntpctl &> /dev/null; then
    if ntpctl -s status | grep -q "clock synced"; then
      ntp_synced=true
      sync_method="OpenNTPD"
    fi
  fi
  
  # Check for running NTP services if not already found
  if [ "$ntp_synced" = false ] && command -v systemctl &> /dev/null; then
    if systemctl is-active --quiet ntpd || systemctl is-active --quiet chronyd || \
       systemctl is-active --quiet systemd-timesyncd || systemctl is-active --quiet openntpd; then
      ntp_synced=true
      sync_method="active NTP service"
    fi
  fi
  
  # Display result
  if [ "$ntp_synced" = true ]; then
    echo -e "  ${GREEN}PASS: Time synchronization is enabled ($sync_method)${NC}"
    return 0
  else
    echo -e "  ${RED}FAIL: No active time synchronization detected${NC}"
    echo -e "  Expected: ${GREEN}Enabled NTP service${NC} (systemd-timesyncd, chronyd, ntpd, or OpenNTPD)"
    return 1
  fi
}

# Check package updates if enabled in config
if should_run_check "packageUpdates"; then
  if ! check_package_updates; then
    ((failures++))
    failed_checks+=("System Updates: Package Updates")
  fi
else
  echo -e "\n${YELLOW}=== System Updates ===${NC}"
  echo -e "${BLUE}Checking pending package updates... ${YELLOW}[SKIPPED]${NC}"
fi

# Function to check SSH configuration
check_ssh_config() {
  echo -e "\n${YELLOW}=== SSH Security ===${NC}"
  echo -e "${BLUE}Checking SSH configuration...${NC}"
  
  # Define the configuration file location
  local ssh_config="/etc/ssh/sshd_config"
  local issues=0
  
  # Check if the file exists
  if [ ! -f "$ssh_config" ]; then
    echo -e "  ${RED}FAIL: SSH configuration file not found at $ssh_config${NC}"
    return 1
  fi
  
  # Check for PermitRootLogin
  root_login=$(grep -i "^PermitRootLogin" "$ssh_config" | awk '{print $2}')
  
  if [ -z "$root_login" ]; then
    # Check for commented lines or if there's no setting at all
    if grep -i "^#.*PermitRootLogin" "$ssh_config" > /dev/null; then
      echo -e "  ${YELLOW}WARNING: PermitRootLogin is commented out, may be using default (permitted)${NC}"
      ((issues++))
    else
      echo -e "  ${YELLOW}WARNING: PermitRootLogin is not set, may be using default (permitted)${NC}"
      ((issues++))
    fi
  elif [[ "$root_login" == "yes" ]]; then
    echo -e "  ${RED}FAIL: Root login is permitted${NC}"
    ((issues++))
  elif [[ "$root_login" == "no" || "$root_login" == "prohibit-password" ]]; then
    echo -e "  ${GREEN}PASS: Root login is disabled or key-only${NC}"
  else
    echo -e "  ${YELLOW}WARNING: Unknown PermitRootLogin value: $root_login${NC}"
    ((issues++))
  fi
  
  # Check for PasswordAuthentication
  password_auth=$(grep -i "^PasswordAuthentication" "$ssh_config" | awk '{print $2}')
  
  if [ -z "$password_auth" ]; then
    # Check for commented lines or if there's no setting at all
    if grep -i "^#.*PasswordAuthentication" "$ssh_config" > /dev/null; then
      echo -e "  ${YELLOW}WARNING: PasswordAuthentication is commented out, may be using default (permitted)${NC}"
      ((issues++))
    else
      echo -e "  ${YELLOW}WARNING: PasswordAuthentication is not set, may be using default (permitted)${NC}"
      ((issues++))
    fi
  elif [[ "$password_auth" == "yes" ]]; then
    echo -e "  ${RED}FAIL: Password authentication is enabled${NC}"
    ((issues++))
  elif [[ "$password_auth" == "no" ]]; then
    echo -e "  ${GREEN}PASS: Password authentication is disabled${NC}"
  else
    echo -e "  ${YELLOW}WARNING: Unknown PasswordAuthentication value: $password_auth${NC}"
    ((issues++))
  fi
  
  # Check for overall security
  if [ $issues -eq 0 ]; then
    echo -e "  ${GREEN}PASS: SSH configuration is secure${NC}"
    return 0
  else
    echo -e "  ${RED}FAIL: SSH configuration has $issues security issue(s)${NC}"
    echo -e "  ${YELLOW}Recommended settings:${NC}"
    echo -e "    PermitRootLogin no"
    echo -e "    PasswordAuthentication no"
    return 1
  fi
}

# Check NTP synchronization if enabled in config
if should_run_check "ntpSync"; then
  if ! check_ntp_sync; then
    ((failures++))
    failed_checks+=("Time Synchronization: NTP")
  fi
else
  echo -e "\n${YELLOW}=== Time Synchronization ===${NC}"
  echo -e "${BLUE}Checking NTP time sync status... ${YELLOW}[SKIPPED]${NC}"
fi

# Function to check logrotate configuration for Solana
check_solana_logrotate() {
  echo -e "\n${YELLOW}=== Log Management ===${NC}"
  echo -e "${BLUE}Checking logrotate configuration for Solana...${NC}"
  
  # Define potential locations and patterns
  local logrotate_dir="/etc/logrotate.d"
  local solana_patterns=("sol" "solana" "solana-validator")
  local found=false
  local config_file=""
  
  # Check if logrotate is installed
  if ! command -v logrotate &> /dev/null; then
    echo -e "  ${RED}FAIL: logrotate is not installed${NC}"
    return 1
  fi
  
  # Check if logrotate.d directory exists
  if [ ! -d "$logrotate_dir" ]; then
    echo -e "  ${RED}FAIL: logrotate.d directory not found${NC}"
    return 1
  fi
  
  # Search for Solana-related logrotate configs in the standard location
  for pattern in "${solana_patterns[@]}"; do
    # Look for exact filenames
    if [ -f "$logrotate_dir/$pattern" ]; then
      found=true
      config_file="$logrotate_dir/$pattern"
      break
    fi
    
    # Look for files containing the pattern
    for file in "$logrotate_dir"/*; do
      if [ -f "$file" ] && grep -q "$pattern" "$file"; then
        found=true
        config_file="$file"
        break 2
      fi
    done
  done
  
  # Check if a solana service is running, which would confirm we should have logrotate
  solana_service_running=false
  if command -v systemctl &> /dev/null; then
    if systemctl is-active --quiet solana || systemctl is-active --quiet sol || systemctl is-active --quiet solana-validator; then
      solana_service_running=true
    fi
  elif ps aux | grep -v grep | grep -E "solana|sol " &> /dev/null; then
    solana_service_running=true
  fi
  
  # Report findings
  if [ "$found" = true ]; then
    echo -e "  ${GREEN}PASS: Solana logrotate configuration found at $config_file${NC}"
    
    # Verify configuration has essential elements
    if grep -q "rotate" "$config_file"; then
      echo -e "  ${GREEN}PASS: Basic rotation settings verified${NC}"
    else
      echo -e "  ${YELLOW}WARNING: Logrotate configuration may be incomplete${NC}"
      echo -e "  ${YELLOW}Recommended to include rotation period and size limits${NC}"
    fi
    return 0
  elif [ "$solana_service_running" = true ]; then
    echo -e "  ${RED}FAIL: Solana service is running but no logrotate configuration found${NC}"
    echo -e "  ${YELLOW}Recommended: Create logrotate configuration at /etc/logrotate.d/sol${NC}"
    return 1
  else
    echo -e "  ${YELLOW}WARNING: No Solana logrotate configuration found${NC}"
    echo -e "  ${YELLOW}Note: This might be acceptable if Solana is not installed on this system${NC}"
    return 0  # No failure if Solana might not be installed
  fi
}

# Check SSH configuration if enabled in config
if should_run_check "sshConfig"; then
  if ! check_ssh_config; then
    ((failures++))
    failed_checks+=("SSH Security: Configuration")
  fi
else
  echo -e "\n${YELLOW}=== SSH Security ===${NC}"
  echo -e "${BLUE}Checking SSH configuration... ${YELLOW}[SKIPPED]${NC}"
fi

# Function to check if unattended upgrades are disabled or enabled based on config
check_unattended_upgrades_disabled() {
  local unattended_upgrades_allowed=$(get_config '.systemChecks.updates.unattendedUpgrades' "false")
  local expected_status
  
  if [ "$unattended_upgrades_allowed" = "true" ]; then
    expected_status="enabled"
  else
    expected_status="disabled"
  fi
  
  echo -e "\n${YELLOW}=== Automatic Updates ===${NC}"
  echo -e "${BLUE}Checking unattended upgrades status...${NC}"
  
  # Skip if not Ubuntu/Debian based
  if ! command -v apt &> /dev/null && [ ! -d "/etc/apt/apt.conf.d" ]; then
    echo -e "  ${YELLOW}WARNING: Not an apt-based system, skipping unattended-upgrades check${NC}"
    return 0
  fi
  
  local enabled=false
  local issues=0
  local apt_based=false
  
  # For Ubuntu/Debian systems
  if command -v dpkg &> /dev/null; then
    apt_based=true
    
    # Check if the unattended-upgrades package is installed
    if dpkg -l | grep -q unattended-upgrades; then
      echo -e "  ${YELLOW}NOTE: unattended-upgrades package is installed${NC}"
      
      # Primary check: verify the service status
      if systemctl is-active --quiet unattended-upgrades; then
        enabled=true
        if [ "$expected_status" = "enabled" ]; then
          echo -e "  ${GREEN}PASS: unattended-upgrades service is active as expected${NC}"
        else
          echo -e "  ${RED}FAIL: unattended-upgrades service is active, should be disabled${NC}"
        fi
      else
        if [ "$expected_status" = "disabled" ]; then
          echo -e "  ${GREEN}PASS: unattended-upgrades service is not active as expected${NC}"
        else
          echo -e "  ${RED}FAIL: unattended-upgrades service is not active, should be enabled${NC}"
        fi
      fi
      
      # Secondary check: verify the timers status
      if systemctl is-enabled --quiet apt-daily.timer; then
        enabled=true
        if [ "$expected_status" = "disabled" ]; then
          echo -e "  ${RED}FAIL: apt-daily timer is enabled, should be disabled${NC}"
        fi
      elif [ "$expected_status" = "enabled" ]; then
        echo -e "  ${RED}FAIL: apt-daily timer is disabled, should be enabled${NC}"
      fi
      
      if systemctl is-enabled --quiet apt-daily-upgrade.timer; then
        enabled=true
        if [ "$expected_status" = "disabled" ]; then
          echo -e "  ${RED}FAIL: apt-daily-upgrade timer is enabled, should be disabled${NC}"
        fi
      elif [ "$expected_status" = "enabled" ]; then
        echo -e "  ${RED}FAIL: apt-daily-upgrade timer is disabled, should be enabled${NC}"
      fi
      
      # Configuration files are only checked for information, not for pass/fail
      if [ -f "/etc/apt/apt.conf.d/20auto-upgrades" ]; then
        if grep -q "APT::Periodic::Update-Package-Lists \"1\"" "/etc/apt/apt.conf.d/20auto-upgrades" ||
           grep -q "APT::Periodic::Unattended-Upgrade \"1\"" "/etc/apt/apt.conf.d/20auto-upgrades"; then
          echo -e "  ${YELLOW}NOTE: Config file 20auto-upgrades has automatic updates configured${NC}"
        fi
      fi
    else
      if [ "$expected_status" = "disabled" ]; then
        echo -e "  ${GREEN}PASS: unattended-upgrades package is not installed as expected${NC}"
      else
        echo -e "  ${RED}FAIL: unattended-upgrades package is not installed, but should be${NC}"
        return 1
      fi
    fi
  fi
  
  # Check for yum-cron on RHEL/CentOS/Fedora systems
  if command -v yum &> /dev/null && rpm -q yum-cron &> /dev/null 2>/dev/null; then
    if systemctl is-active --quiet yum-cron; then
      enabled=true
      if [ "$expected_status" = "disabled" ]; then
        echo -e "  ${RED}FAIL: yum-cron service is active, should be disabled${NC}"
      else
        echo -e "  ${GREEN}PASS: yum-cron service is active as expected${NC}"
      fi
    elif [ "$expected_status" = "enabled" ]; then
      echo -e "  ${RED}FAIL: yum-cron service is not active, should be enabled${NC}"
    fi
    
    if [ -f "/etc/yum/yum-cron.conf" ] && grep -q "apply_updates = yes" "/etc/yum/yum-cron.conf"; then
      echo -e "  ${YELLOW}NOTE: yum-cron is configured to automatically apply updates${NC}"
    fi
  fi
  
  # Check for dnf-automatic on newer RHEL/Fedora systems
  if command -v dnf &> /dev/null && rpm -q dnf-automatic &> /dev/null 2>/dev/null; then
    if systemctl is-active --quiet dnf-automatic.timer; then
      enabled=true
      if [ "$expected_status" = "disabled" ]; then
        echo -e "  ${RED}FAIL: dnf-automatic timer is active, should be disabled${NC}"
      else
        echo -e "  ${GREEN}PASS: dnf-automatic timer is active as expected${NC}"
      fi
    elif [ "$expected_status" = "enabled" ]; then
      echo -e "  ${RED}FAIL: dnf-automatic timer is not active, should be enabled${NC}"
    fi
    
    if [ -f "/etc/dnf/automatic.conf" ] && grep -q "apply_updates = yes" "/etc/dnf/automatic.conf"; then
      echo -e "  ${YELLOW}NOTE: dnf-automatic is configured to automatically apply updates${NC}"
    fi
  fi
  
  # Display results
  if ([ "$enabled" = true ] && [ "$expected_status" = "enabled" ]) || 
     ([ "$enabled" = false ] && [ "$expected_status" = "disabled" ]); then
    if [ "$apt_based" = true ]; then
      echo -e "  ${GREEN}PASS: Automatic update services are in expected state: $expected_status${NC}"
    fi
    return 0
  else
    echo -e "  ${RED}FAIL: Automatic update services are not in expected state${NC}"
    echo -e "  Current status: ${RED}$([ "$enabled" = true ] && echo 'enabled' || echo 'disabled')${NC}"
    echo -e "  Expected status: ${GREEN}$expected_status${NC}"
    
    if [ "$expected_status" = "disabled" ]; then
      echo -e "  ${YELLOW}To disable automatic updates:${NC}"
      echo -e "  - For Ubuntu/Debian: 'systemctl disable --now unattended-upgrades'"
      echo -e "  - For Ubuntu/Debian: 'systemctl disable --now apt-daily.timer apt-daily-upgrade.timer'"
      echo -e "  - For RHEL/CentOS: 'systemctl disable --now yum-cron'"
      echo -e "  - For Fedora/newer RHEL: 'systemctl disable --now dnf-automatic.timer'"
    else
      echo -e "  ${YELLOW}To enable automatic updates:${NC}"
      echo -e "  - For Ubuntu/Debian: 'apt install unattended-upgrades && systemctl enable --now unattended-upgrades'"
      echo -e "  - For Ubuntu/Debian: 'systemctl enable --now apt-daily.timer apt-daily-upgrade.timer'"
      echo -e "  - For RHEL/CentOS: 'yum install yum-cron && systemctl enable --now yum-cron'"
      echo -e "  - For Fedora/newer RHEL: 'dnf install dnf-automatic && systemctl enable --now dnf-automatic.timer'"
    fi
    
    return 1
  fi
}

# Check Solana logrotate configuration if enabled in config
if should_run_check "solanaLogrotate"; then
  if ! check_solana_logrotate; then
    ((failures++))
    failed_checks+=("Log Management: Solana logrotate")
  fi
else
  echo -e "\n${YELLOW}=== Log Management ===${NC}"
  echo -e "${BLUE}Checking logrotate configuration for Solana... ${YELLOW}[SKIPPED]${NC}"
fi

# Function to check if Ubuntu needs a reboot
check_reboot_required() {
  echo -e "\n${YELLOW}=== System Reboot Status ===${NC}"
  echo -e "${BLUE}Checking if system requires a reboot...${NC}"
  
  # Only proceed if this is an Ubuntu/Debian system
  if ! command -v apt &> /dev/null; then
    echo -e "  ${YELLOW}WARNING: Not an apt-based system, skipping reboot-required check${NC}"
    return 0
  fi
  
  # Check for the reboot-required file
  if [ -f /var/run/reboot-required ]; then
    echo -e "  ${RED}FAIL: System requires a reboot${NC}"
    if [ -f /var/run/reboot-required.pkgs ]; then
      echo -e "  ${YELLOW}Packages requiring reboot:${NC}"
      cat /var/run/reboot-required.pkgs | sed 's/^/    /'
    fi
    echo -e "  ${YELLOW}Run 'sudo reboot' to apply all pending changes${NC}"
    return 1
  else
    echo -e "  ${GREEN}PASS: System does not require a reboot${NC}"
    return 0
  fi
}

# Check if unattended upgrades are disabled if enabled in config
if should_run_check "unattendedUpgrades"; then
  if ! check_unattended_upgrades_disabled; then
    ((failures++))
    failed_checks+=("Automatic Updates: unattended-upgrades")
  fi
else
  echo -e "\n${YELLOW}=== Automatic Updates ===${NC}"
  echo -e "${BLUE}Checking unattended upgrades status... ${YELLOW}[SKIPPED]${NC}"
fi

# Check if system requires a reboot if enabled in config
if should_run_check "rebootStatus"; then
  if ! check_reboot_required; then
    ((failures++))
    failed_checks+=("System Reboot Status: reboot required")
  fi
else
  echo -e "\n${YELLOW}=== System Reboot Status ===${NC}"
  echo -e "${BLUE}Checking if system requires a reboot... ${YELLOW}[SKIPPED]${NC}"
fi

# Function to check NIC ring buffer sizes
check_nic_ring_buffers() {
  echo -e "\n${YELLOW}=== Network Interface Ring Buffers ===${NC}"
  echo -e "${BLUE}Checking NIC ring buffer sizes...${NC}"
  
  local issues=0
  local total_nics=0
  
  # Check if ethtool is available
  if ! command -v ethtool &> /dev/null; then
    echo -e "  ${RED}FAIL: ethtool is not installed${NC}"
    echo -e "  ${YELLOW}Install with: apt-get install ethtool (Debian/Ubuntu) or yum install ethtool (RHEL/CentOS)${NC}"
    return 1
  fi
  
  # Get all physical network interfaces (excluding lo, veth, docker, etc.)
  for nic in /sys/class/net/*; do
    nic_name=$(basename "$nic")
    
    # Skip virtual interfaces
    if [[ "$nic_name" == "lo" ]] || [[ "$nic_name" == veth* ]] || [[ "$nic_name" == docker* ]] || 
       [[ "$nic_name" == br-* ]] || [[ "$nic_name" == virbr* ]] || [[ "$nic_name" == tun* ]] ||
       [[ "$nic_name" == tap* ]]; then
      continue
    fi
    
    # Check if it's a physical interface
    if [ ! -d "/sys/class/net/$nic_name/device" ]; then
      continue
    fi
    
    ((total_nics++))
    
    # Get current ring buffer settings
    ring_info=$(ethtool -g "$nic_name" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
      echo -e "  ${YELLOW}WARNING: Cannot get ring buffer info for $nic_name${NC}"
      continue
    fi
    
    # Parse current and maximum values - handle different ethtool output formats
    rx_max=$(echo "$ring_info" | grep -A1 "Pre-set maximums:" | grep -E "(RX|Rx):" | awk '{print $2}')
    rx_current=$(echo "$ring_info" | grep -A1 "Current hardware settings:" | grep -E "(RX|Rx):" | awk '{print $2}')
    
    # Try multiple patterns for TX values as different drivers use different formats
    tx_max=$(echo "$ring_info" | grep -A1 "Pre-set maximums:" | grep -E "(TX|Tx):" | awk '{print $2}')
    tx_current=$(echo "$ring_info" | grep -A1 "Current hardware settings:" | grep -E "(TX|Tx):" | awk '{print $2}')
    
    # Some drivers might not separate RX/TX, try alternative parsing
    if [ -z "$tx_max" ] || [ -z "$tx_current" ]; then
      # Try parsing TX from the same line as RX or different section
      tx_max=$(echo "$ring_info" | grep -A5 "Pre-set maximums:" | grep -E "(TX|Tx)" | awk '{print $2}')
      tx_current=$(echo "$ring_info" | grep -A5 "Current hardware settings:" | grep -E "(TX|Tx)" | awk '{print $2}')
    fi
    
    # If still empty, some drivers might use different terminology
    if [ -z "$tx_max" ] || [ -z "$tx_current" ]; then
      # Try to find TX in the raw output with different patterns
      tx_max=$(echo "$ring_info" | grep -i "tx.*max" | awk '{print $NF}' | grep -E '^[0-9]+$')
      tx_current=$(echo "$ring_info" | grep -i "tx.*current" | awk '{print $NF}' | grep -E '^[0-9]+$')
    fi
    
    # Check if values are at maximum
    local nic_ok=true
    
    if [ -n "$rx_max" ] && [ -n "$rx_current" ]; then
      # Clean values to remove any whitespace  
      rx_max_clean=$(echo "$rx_max" | tr -d '[:space:]')
      rx_current_clean=$(echo "$rx_current" | tr -d '[:space:]')
      
      # Use numeric comparison
      if [ "$rx_current_clean" -lt "$rx_max_clean" ] 2>/dev/null; then
        echo -e "  ${RED}FAIL: $nic_name RX ring buffer not at maximum${NC}"
        echo -e "    Current: $rx_current_clean, Maximum: $rx_max_clean"
        nic_ok=false
        ((issues++))
      fi
    fi
    
    # Only check TX if we have valid values
    if [ -n "$tx_max" ] && [ -n "$tx_current" ]; then
      # Clean values to remove any whitespace
      tx_max_clean=$(echo "$tx_max" | tr -d '[:space:]')
      tx_current_clean=$(echo "$tx_current" | tr -d '[:space:]')
      
      # Use numeric comparison
      if [ "$tx_current_clean" -lt "$tx_max_clean" ] 2>/dev/null; then
        echo -e "  ${RED}FAIL: $nic_name TX ring buffer not at maximum${NC}"
        echo -e "    Current: $tx_current_clean, Maximum: $tx_max_clean"
        nic_ok=false
        ((issues++))
      fi
    elif [ -n "$tx_max" ] || [ -n "$tx_current" ]; then
      # Partial TX info available but incomplete
      echo -e "  ${YELLOW}WARNING: $nic_name TX ring buffer info partially available${NC}"
    fi
    
    if [ "$nic_ok" = true ]; then
      if [ -n "$tx_current" ]; then
        echo -e "  ${GREEN}PASS: $nic_name ring buffers are at maximum (RX: $rx_current, TX: $tx_current)${NC}"
      else
        echo -e "  ${GREEN}PASS: $nic_name RX ring buffer is at maximum (RX: $rx_current)${NC}"
        echo -e "  ${YELLOW}NOTE: $nic_name TX ring buffer info not available from driver${NC}"
      fi
    fi
  done
  
  if [ $total_nics -eq 0 ]; then
    echo -e "  ${YELLOW}WARNING: No physical network interfaces found${NC}"
    return 0
  fi
  
  if [ $issues -eq 0 ]; then
    echo -e "  ${GREEN}PASS: All NIC ring buffers are configured at maximum capacity${NC}"
    return 0
  else
    echo -e "  ${RED}FAIL: $issues NIC ring buffer(s) not at maximum capacity${NC}"
    echo -e "  ${YELLOW}To fix: Use ethtool -G <interface> rx <max_value> tx <max_value>${NC}"
    return 1
  fi
}

# Function to check ethtool-ring-buffers.service
check_ethtool_service() {
  echo -e "\n${YELLOW}=== Network Services ===${NC}"
  echo -e "${BLUE}Checking ethtool-ring-buffers.service...${NC}"
  
  # Check if systemctl command exists
  if ! command -v systemctl &> /dev/null; then
    echo -e "  ${RED}FAIL: systemctl command not found. Is this a systemd-based system?${NC}"
    return 1
  fi
  
  # Check if the service exists
  if ! systemctl list-unit-files | grep -q ethtool-ring-buffers.service; then
    echo -e "  ${RED}FAIL: ethtool-ring-buffers.service is not installed${NC}"
    echo -e "  ${YELLOW}This service should be created to ensure ring buffers are set at boot${NC}"
    return 1
  fi
  
  # Check if service is enabled
  if systemctl is-enabled ethtool-ring-buffers.service &> /dev/null; then
    enabled_status="${GREEN}enabled${NC}"
  else
    enabled_status="${RED}disabled${NC}"
  fi
  
  # Check if service is running
  if systemctl is-active ethtool-ring-buffers.service &> /dev/null; then
    active_status="${GREEN}active${NC}"
  else
    active_status="${RED}inactive${NC}"
  fi
  
  # Display status
  if [ "$enabled_status" = "${GREEN}enabled${NC}" ] && [ "$active_status" = "${GREEN}active${NC}" ]; then
    echo -e "  ${GREEN}PASS: ethtool-ring-buffers.service is enabled and active${NC}"
    return 0
  else
    echo -e "  ${RED}FAIL: ethtool-ring-buffers.service status issue${NC}"
    echo -e "  Service status: $active_status, boot status: $enabled_status"
    echo -e "  Expected: ${GREEN}active${NC} and ${GREEN}enabled${NC}"
    return 1
  fi
}

# Function to check if C-states are disabled
check_cstates_disabled() {
  echo -e "\n${YELLOW}=== CPU C-State Configuration ===${NC}"
  echo -e "${BLUE}Checking C-state status...${NC}"
  
  local cstates_enabled=false
  
  # Check kernel command line for intel_idle.max_cstate
  if grep -q "intel_idle.max_cstate=0" /proc/cmdline; then
    echo -e "  ${GREEN}PASS: C-states disabled via kernel parameter (intel_idle.max_cstate=0)${NC}"
    return 0
  fi
  
  # Check kernel command line for processor.max_cstate
  if grep -q "processor.max_cstate=0" /proc/cmdline; then
    echo -e "  ${GREEN}PASS: C-states disabled via kernel parameter (processor.max_cstate=0)${NC}"
    return 0
  fi
  
  # Check sysfs for C-state status
  local cpu_idle_dir="/sys/devices/system/cpu/cpu0/cpuidle"
  if [ -d "$cpu_idle_dir" ]; then
    # Count enabled C-states
    local enabled_cstates=0
    for state in "$cpu_idle_dir"/state*; do
      if [ -f "$state/disable" ]; then
        if [ "$(cat "$state/disable")" -eq 0 ]; then
          ((enabled_cstates++))
        fi
      fi
    done
    
    if [ $enabled_cstates -le 1 ]; then
      echo -e "  ${GREEN}PASS: C-states are effectively disabled (only C0 enabled)${NC}"
      return 0
    else
      echo -e "  ${RED}FAIL: $enabled_cstates C-states are enabled${NC}"
      echo -e "  ${YELLOW}To disable: Add 'intel_idle.max_cstate=0' or 'processor.max_cstate=0' to kernel parameters${NC}"
      return 1
    fi
  else
    echo -e "  ${YELLOW}WARNING: Unable to determine C-state status from sysfs${NC}"
    echo -e "  ${YELLOW}Check kernel parameters for max_cstate settings${NC}"
    return 0
  fi
}

# Function to check AMD P-state EPP
check_amd_pstate_epp() {
  echo -e "\n${YELLOW}=== AMD P-State EPP Configuration ===${NC}"
  echo -e "${BLUE}Checking energy performance preference...${NC}"
  
  # Check if this is an AMD system
  if ! grep -q "AMD" /proc/cpuinfo; then
    echo -e "  ${YELLOW}WARNING: Not an AMD processor, skipping AMD P-state EPP check${NC}"
    return 0
  fi
  
  # Check if amd-pstate driver is active
  local driver_file="/sys/devices/system/cpu/cpu0/cpufreq/scaling_driver"
  if [ -f "$driver_file" ]; then
    driver=$(cat "$driver_file")
    if [[ "$driver" != "amd-pstate-epp" ]] && [[ "$driver" != "amd-pstate" ]]; then
      echo -e "  ${YELLOW}WARNING: AMD P-state driver not active (current: $driver)${NC}"
      return 0
    fi
  fi
  
  # Check EPP settings
  local epp_file="/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference"
  if [ -f "$epp_file" ]; then
    local epp_value=$(cat "$epp_file")
    if [ "$epp_value" = "performance" ]; then
      echo -e "  ${GREEN}PASS: EPP set to performance mode${NC}"
      return 0
    else
      echo -e "  ${RED}FAIL: EPP not set to performance mode${NC}"
      echo -e "  Current: ${YELLOW}$epp_value${NC}"
      echo -e "  Expected: ${GREEN}performance${NC}"
      return 1
    fi
  else
    echo -e "  ${YELLOW}WARNING: EPP not available on this system${NC}"
    return 0
  fi
}

# Function to check isolated CPUs
check_isolated_cpus() {
  echo -e "\n${YELLOW}=== CPU Isolation ===${NC}"
  echo -e "${BLUE}Checking isolated CPU cores...${NC}"
  
  # Check kernel command line for isolcpus
  if grep -q "isolcpus=" /proc/cmdline; then
    local isolated=$(grep -o "isolcpus=[^ ]*" /proc/cmdline | cut -d= -f2)
    echo -e "  ${GREEN}PASS: CPU cores isolated: $isolated${NC}"
    return 0
  else
    echo -e "  ${YELLOW}WARNING: No CPU cores isolated${NC}"
    echo -e "  ${YELLOW}Consider using isolcpus kernel parameter for dedicated workloads${NC}"
    return 0  # Not a failure, just informational
  fi
}

# Function to check CPU power limits
check_cpu_power_limits() {
  echo -e "\n${YELLOW}=== CPU Power Limits ===${NC}"
  echo -e "${BLUE}Checking CPU power limit configuration...${NC}"
  
  # Check Intel RAPL power limits
  local rapl_base="/sys/class/powercap/intel-rapl"
  if [ -d "$rapl_base" ]; then
    echo -e "  ${BLUE}Intel RAPL power limits detected${NC}"
    
    for pkg in "$rapl_base"/intel-rapl:*; do
      if [ -d "$pkg" ] && [[ "$pkg" == *":0"* ]]; then
        if [ -f "$pkg/constraint_0_power_limit_uw" ]; then
          local limit=$(cat "$pkg/constraint_0_power_limit_uw")
          local limit_watts=$((limit / 1000000))
          echo -e "  Package power limit: ${YELLOW}${limit_watts}W${NC}"
        fi
        
        if [ -f "$pkg/enabled" ]; then
          local enabled=$(cat "$pkg/enabled")
          if [ "$enabled" -eq 1 ]; then
            echo -e "  ${YELLOW}WARNING: Power limits are enabled${NC}"
            echo -e "  ${YELLOW}This may limit performance under heavy load${NC}"
          else
            echo -e "  ${GREEN}PASS: Power limits are disabled${NC}"
          fi
        fi
      fi
    done
    return 0
  else
    echo -e "  ${GREEN}PASS: No Intel RAPL power limits found${NC}"
    return 0
  fi
}

# Function to check NVMe drive wear levels
check_nvme_wear() {
  echo -e "\n${YELLOW}=== NVMe Drive Health ===${NC}"
  echo -e "${BLUE}Checking NVMe drive wear levels...${NC}"
  
  local max_wear_threshold=$(get_config '.systemChecks.storage.maxNvmeWearPercent' "80")
  local issues=0
  local total_drives=0
  local nvme_found=false
  
  # Check if nvme command is available
  if ! command -v nvme &> /dev/null; then
    echo -e "  ${RED}FAIL: nvme-cli is not installed${NC}"
    echo -e "  ${YELLOW}Install with: apt-get install nvme-cli (Debian/Ubuntu) or yum install nvme-cli (RHEL/CentOS)${NC}"
    return 1
  fi
  
  # Check for NVMe drives in the system
  for i in {0..15}; do
    device="/dev/nvme${i}n1"
    if [ -b "$device" ]; then
      nvme_found=true
      ((total_drives++))
      
      # Get SMART log data
      smart_data=$(nvme smart-log "$device" 2>/dev/null)
      
      if [ $? -ne 0 ]; then
        echo -e "  ${YELLOW}WARNING: Cannot read SMART data for $device (may require sudo)${NC}"
        continue
      fi
      
      # Extract percentage used
      percentage_used=$(echo "$smart_data" | grep -i "percentage_used" | awk '{print $3}' | tr -d '%')
      
      if [ -z "$percentage_used" ]; then
        echo -e "  ${YELLOW}WARNING: Cannot determine wear level for $device${NC}"
        continue
      fi
      
      # Clean the value to ensure it's numeric
      percentage_used=$(echo "$percentage_used" | tr -d '[:space:]')
      
      # Check if wear level exceeds threshold
      if [ "$percentage_used" -ge "$max_wear_threshold" ] 2>/dev/null; then
        echo -e "  ${RED}FAIL: $device wear level is ${percentage_used}% (threshold: ${max_wear_threshold}%)${NC}"
        ((issues++))
      else
        echo -e "  ${GREEN}PASS: $device wear level is ${percentage_used}% (threshold: ${max_wear_threshold}%)${NC}"
      fi
    fi
  done
  
  if [ "$nvme_found" = false ]; then
    echo -e "  ${YELLOW}WARNING: No NVMe drives found in the system${NC}"
    return 0  # Not a failure if no NVMe drives present
  fi
  
  if [ $issues -eq 0 ]; then
    echo -e "  ${GREEN}PASS: All $total_drives NVMe drive(s) are within acceptable wear levels${NC}"
    return 0
  else
    echo -e "  ${RED}FAIL: $issues of $total_drives NVMe drive(s) exceed wear threshold${NC}"
    echo -e "  ${YELLOW}Consider replacing drives with wear levels >= ${max_wear_threshold}%${NC}"
    return 1
  fi
}

# Check NIC ring buffers if enabled in config
if should_run_check "nicRingBuffers"; then
  if ! check_nic_ring_buffers; then
    ((failures++))
    failed_checks+=("Network Interface Ring Buffers")
  fi
else
  echo -e "\n${YELLOW}=== Network Interface Ring Buffers ===${NC}"
  echo -e "${BLUE}Checking NIC ring buffer sizes... ${YELLOW}[SKIPPED]${NC}"
fi

# Check ethtool-ring-buffers service if enabled in config
if should_run_check "ethtoolService"; then
  if ! check_ethtool_service; then
    ((failures++))
    failed_checks+=("Network Services: ethtool-ring-buffers.service")
  fi
else
  echo -e "\n${YELLOW}=== Network Services ===${NC}"
  echo -e "${BLUE}Checking ethtool-ring-buffers.service... ${YELLOW}[SKIPPED]${NC}"
fi

# Check C-states if enabled in config
if should_run_check "cstatesDisabled"; then
  if ! check_cstates_disabled; then
    ((failures++))
    failed_checks+=("CPU Power Management: C-states")
  fi
else
  echo -e "\n${YELLOW}=== CPU C-State Configuration ===${NC}"
  echo -e "${BLUE}Checking C-state status... ${YELLOW}[SKIPPED]${NC}"
fi

# Check AMD P-state EPP if enabled in config
if should_run_check "amdPstateEpp"; then
  if ! check_amd_pstate_epp; then
    ((failures++))
    failed_checks+=("CPU Power Management: AMD P-state EPP")
  fi
else
  echo -e "\n${YELLOW}=== AMD P-State EPP Configuration ===${NC}"
  echo -e "${BLUE}Checking energy performance preference... ${YELLOW}[SKIPPED]${NC}"
fi

# Check isolated CPUs if enabled in config
if should_run_check "isolatedCpus"; then
  if ! check_isolated_cpus; then
    ((failures++))
    failed_checks+=("CPU Configuration: Isolated CPUs")
  fi
else
  echo -e "\n${YELLOW}=== CPU Isolation ===${NC}"
  echo -e "${BLUE}Checking isolated CPU cores... ${YELLOW}[SKIPPED]${NC}"
fi

# Check CPU power limits if enabled in config
if should_run_check "cpuPowerLimits"; then
  if ! check_cpu_power_limits; then
    ((failures++))
    failed_checks+=("CPU Configuration: Power Limits")
  fi
else
  echo -e "\n${YELLOW}=== CPU Power Limits ===${NC}"
  echo -e "${BLUE}Checking CPU power limit configuration... ${YELLOW}[SKIPPED]${NC}"
fi

# Check NVMe wear levels if enabled in config
if should_run_check "nvmeWear"; then
  if ! check_nvme_wear; then
    ((failures++))
    failed_checks+=("Storage: NVMe Wear Levels")
  fi
else
  echo -e "\n${YELLOW}=== NVMe Drive Health ===${NC}"
  echo -e "${BLUE}Checking NVMe drive wear levels... ${YELLOW}[SKIPPED]${NC}"
fi

# Summary - Always show this part even in quiet mode
if [ "$QUIET_MODE" = true ]; then
  # Restore stdout for the summary
  exec 1>&3
fi

echo ""
echo -e "${BLUE}Health check complete.${NC}"
if [ $failures -eq 0 ]; then
  echo -e "${GREEN}All checks passed successfully.${NC}"
  exit 0
else
  echo -e "${RED}$failures check(s) failed.${NC}"
  
  # Print summary of failing checks
  echo -e "${YELLOW}Failed checks:${NC}"
  for check in "${failed_checks[@]}"; do
    echo -e "  ${RED}✗${NC} $check"
  done
  exit 1
fi

