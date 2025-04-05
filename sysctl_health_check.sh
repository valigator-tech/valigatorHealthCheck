#!/bin/bash

# We don't want to exit immediately on error since we want to run all checks

# Array of sysctl checks in format: "parameter expected_value"
declare -A checks=(
  ["net.ipv4.tcp_rmem"]="10240 87380 12582912"
  ["net.ipv4.tcp_wmem"]="10240 87380 12582912"
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

  echo "Checking $param..."
  
  # Get the current value
  current=$(sysctl -n "$param" 2>/dev/null)
  
  # Check if sysctl command was successful
  if [ $? -ne 0 ]; then
    echo "ERROR: Could not retrieve $param value. This may not be a Linux system or you don't have permission."
    return 1
  fi
  
  # Normalize whitespace in both expected and current values
  normalized_expected=$(normalize_whitespace "$expected")
  normalized_current=$(normalize_whitespace "$current")
  
  # Check if the normalized values match
  if [ "$normalized_current" != "$normalized_expected" ]; then
    echo "  FAIL: $param value is incorrect."
    echo "  Current value: $current"
    echo "  Expected value: $expected"
    return 1
  else
    echo "  PASS: $param value is correct: $current"
    return 0
  fi
}

# Run all checks
echo "Starting sysctl health checks..."
for param in "${!checks[@]}"; do
  if ! check_sysctl "$param" "${checks[$param]}"; then
    ((failures++))
  fi
done

# Summary
echo ""
echo "Health check complete."
if [ $failures -eq 0 ]; then
  echo "All checks passed successfully."
  exit 0
else
  echo "$failures check(s) failed."
  exit 1
fi