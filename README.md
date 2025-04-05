# Valigator Health Check

A comprehensive system health check script for Linux servers, designed to verify optimal system configuration for high-performance environments.

## Overview

This script checks various system settings and configurations to ensure your Linux server is optimally configured. It features color-coded output to easily identify passing and failing checks, and organizes checks into logical categories.

The script verifies the following aspects of your system:

- **TCP Buffer Sizes**: Checks for optimal TCP memory buffer configurations
- **TCP Optimization**: Validates congestion control algorithms and other TCP performance settings 
- **Kernel Optimization**: Verifies timer migration, hung task timeout, and other kernel parameters
- **Virtual Memory Tuning**: Checks swappiness, memory maps, dirty ratio, and other VM subsystem parameters
- **Solana Specific Tuning**: Validates network buffer settings required for optimal Solana node performance
- **CPU Governor Settings**: Ensures CPU cores are set to performance governor mode
- **CPU Performance**: Verifies that CPU boost/turbo is enabled
- **CPU Driver**: Ensures that the p-state CPU scaling driver is being used
- **Memory Management**: Confirms swap is disabled
- **Security Services**: Checks that fail2ban is installed, enabled, and running
- **System Updates**: Validates that there are no more than 5 package updates pending
- **Automatic Updates**: Verifies that unattended upgrades and automatic updates are disabled
- **Time Synchronization**: Ensures some form of NTP time synchronization is active
- **SSH Security**: Verifies SSH is configured securely with root login and password authentication disabled
- **Log Management**: Checks for proper logrotate configuration for Solana services

## Usage

```bash
# Basic usage (requires root/sudo)
sudo ./health_check.sh

# Skip the fail2ban check
sudo ./health_check.sh --skip-fail2ban

# Skip the package updates check
sudo ./health_check.sh --skip-package-updates 

# Skip the SSH security configuration check
sudo ./health_check.sh --skip-ssh-check

# Skip multiple checks
sudo ./health_check.sh --skip-fail2ban --skip-package-updates --skip-ssh-check

# Display help
./health_check.sh --help
```

## Requirements

- Linux-based operating system
- Root/sudo access
- Bash shell

## Output

The script provides color-coded output for easy interpretation:
- 🟢 Green: Passing checks
- 🔴 Red: Failing checks that need attention
- 🟡 Yellow: Warnings or skipped checks
- 🔵 Blue: Informational messages

## Notes

- For TCP congestion control, the script expects "westwood" but will accept "bbr" with a warning
- For kernel.pid_max, the script checks if the value is equal to or greater than the expected value
- For vm.swappiness, the script accepts any value of 30 or lower
- CPU boost check handles both Intel and AMD-specific boost mechanisms
- NTP check supports multiple time synchronization methods (systemd-timesyncd, chronyd, ntpd, OpenNTPD)
- Package update checker automatically detects apt, dnf, yum, pacman, or zypper package managers