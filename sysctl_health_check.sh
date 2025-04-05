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
  
  # Normalize whitespace in both expected and current values
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

# Run all checks
echo -e "${BLUE}Starting sysctl health checks...${NC}"

# Run checks by category
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