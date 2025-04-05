#!/bin/bash

# We don't want to exit immediately on error since we want to run all checks

# Define colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
SKIP_FAIL2BAN=false
SKIP_PACKAGE_UPDATES=false
SKIP_SSH_CHECK=false

# Parse command line options
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --skip-fail2ban)
      SKIP_FAIL2BAN=true
      shift
      ;;
    --skip-package-updates)
      SKIP_PACKAGE_UPDATES=true
      shift
      ;;
    --skip-ssh-check)
      SKIP_SSH_CHECK=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo "Options:"
      echo "  --skip-fail2ban         Skip the fail2ban check"
      echo "  --skip-package-updates  Skip the package updates check" 
      echo "  --skip-ssh-check        Skip the SSH security configuration check"
      echo "  -h, --help              Display this help message and exit"
      exit 0
      ;;
    *)
      echo "Unknown option: $key"
      echo "Use --help to see available options"
      exit 1
      ;;
  esac
done

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
  local expected="performance"
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

# Check fail2ban service (unless skipped)
if [ "$SKIP_FAIL2BAN" = false ]; then
  if ! check_fail2ban; then
    ((failures++))
  fi
else
  echo -e "\n${YELLOW}=== Security Services ===${NC}"
  echo -e "${BLUE}Checking fail2ban service... ${YELLOW}[SKIPPED]${NC}"
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

# Function to check if p-state driver is being used
check_pstate_driver() {
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
    
    # Check if the driver contains "pstate"
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
    echo -e "  ${RED}FAIL: Could not determine CPU scaling driver${NC}"
    return 1
  fi
}

# Check CPU boost status
if ! check_cpu_boost; then
  ((failures++))
fi

# Check CPU p-state driver
if ! check_pstate_driver; then
  ((failures++))
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

# Check package updates (unless skipped)
if [ "$SKIP_PACKAGE_UPDATES" = false ]; then
  if ! check_package_updates; then
    ((failures++))
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

# Check NTP synchronization
if ! check_ntp_sync; then
  ((failures++))
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

# Check SSH configuration (unless skipped)
if [ "$SKIP_SSH_CHECK" = false ]; then
  if ! check_ssh_config; then
    ((failures++))
  fi
else
  echo -e "\n${YELLOW}=== SSH Security ===${NC}"
  echo -e "${BLUE}Checking SSH configuration... ${YELLOW}[SKIPPED]${NC}"
fi

# Function to check if unattended upgrades are disabled
check_unattended_upgrades_disabled() {
  echo -e "\n${YELLOW}=== Automatic Updates ===${NC}"
  echo -e "${BLUE}Checking if unattended upgrades are disabled...${NC}"
  
  # Skip if not Ubuntu/Debian based
  if ! command -v apt &> /dev/null && [ ! -f "/etc/apt/apt.conf.d" ]; then
    echo -e "  ${YELLOW}WARNING: Not an apt-based system, skipping unattended-upgrades check${NC}"
    return 0
  fi
  
  local enabled=false
  local issues=0
  
  # Check if the unattended-upgrades package is installed
  if dpkg -l | grep -q unattended-upgrades; then
    # Check key configuration files
    if [ -f "/etc/apt/apt.conf.d/20auto-upgrades" ]; then
      if grep -q "APT::Periodic::Update-Package-Lists \"1\"" "/etc/apt/apt.conf.d/20auto-upgrades" ||
         grep -q "APT::Periodic::Unattended-Upgrade \"1\"" "/etc/apt/apt.conf.d/20auto-upgrades"; then
        enabled=true
        ((issues++))
      fi
    fi
    
    if [ -f "/etc/apt/apt.conf.d/50unattended-upgrades" ]; then
      if grep -q -v "^\/\/" "/etc/apt/apt.conf.d/50unattended-upgrades" | grep -q "Unattended-Upgrade::Allowed-Origins"; then
        # Check if there are uncommented allowed origins
        enabled=true
        ((issues++))
      fi
    fi
    
    # Check if the service is active
    if systemctl is-active --quiet unattended-upgrades; then
      enabled=true
      ((issues++))
      echo -e "  ${RED}FAIL: unattended-upgrades service is active${NC}"
    fi
    
    # Check if the apt-daily timers are enabled
    if systemctl is-enabled --quiet apt-daily.timer || systemctl is-enabled --quiet apt-daily-upgrade.timer; then
      enabled=true
      ((issues++))
      echo -e "  ${RED}FAIL: apt-daily timers are enabled${NC}"
    fi
  fi
  
  # Check for yum-cron on RHEL/CentOS/Fedora systems
  if command -v yum &> /dev/null && rpm -q yum-cron &> /dev/null; then
    if [ -f "/etc/yum/yum-cron.conf" ] && grep -q "apply_updates = yes" "/etc/yum/yum-cron.conf"; then
      enabled=true
      ((issues++))
      echo -e "  ${RED}FAIL: yum-cron is configured to automatically apply updates${NC}"
    fi
  fi
  
  # Check for dnf-automatic on newer RHEL/Fedora systems
  if command -v dnf &> /dev/null && rpm -q dnf-automatic &> /dev/null; then
    if [ -f "/etc/dnf/automatic.conf" ] && grep -q "apply_updates = yes" "/etc/dnf/automatic.conf"; then
      enabled=true
      ((issues++))
      echo -e "  ${RED}FAIL: dnf-automatic is configured to automatically apply updates${NC}"
    fi
  fi
  
  # Display results
  if [ "$enabled" = false ]; then
    echo -e "  ${GREEN}PASS: Automatic updates are disabled${NC}"
    return 0
  else
    echo -e "  ${RED}FAIL: Automatic updates appear to be enabled${NC}"
    echo -e "  ${YELLOW}Recommended actions:${NC}"
    echo -e "  - For Ubuntu/Debian: 'apt remove unattended-upgrades'"
    echo -e "  - For Ubuntu/Debian: Edit /etc/apt/apt.conf.d/20auto-upgrades and set Update-Package-Lists and Unattended-Upgrade to \"0\""
    echo -e "  - For RHEL/CentOS: 'systemctl disable --now yum-cron' or edit /etc/yum/yum-cron.conf"
    echo -e "  - For Fedora/newer RHEL: 'systemctl disable --now dnf-automatic.timer' or edit /etc/dnf/automatic.conf"
    return 1
  fi
}

# Check Solana logrotate configuration
if ! check_solana_logrotate; then
  ((failures++))
fi

# Check if unattended upgrades are disabled
if ! check_unattended_upgrades_disabled; then
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