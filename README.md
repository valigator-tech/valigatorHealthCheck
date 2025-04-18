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
- **System Reboot Status**: Checks if Ubuntu system requires a reboot and fails if a reboot is needed
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

# Quiet mode (only show final results)
sudo ./health_check.sh --quiet

# Quiet mode with short flag
sudo ./health_check.sh -q

# Use a custom configuration file
sudo ./health_check.sh --config /path/to/custom-config.json

# Display help
./health_check.sh --help
```

## Configuration

The script uses a JSON configuration file (`config.json` by default) that contains all the expected values for the checks. This allows you to customize the expected settings without modifying the script.

You can specify a custom configuration file with the `-c` or `--config` option:

```bash
sudo ./health_check.sh --config /path/to/custom-config.json
```

### Configuration File Format

The configuration file is structured as follows:

```json
{
  "sysctlChecks": {
    "Category Name": {
      "sysctl.parameter": "expected value"
    }
  },
  "systemChecks": {
    "cpu": {
      "governor": "performance",
      "boost": "enabled",
      "driver": "pstate"
    },
    "security": {
      "fail2ban": {
        "enabled": true,
        "running": true
      },
      "ssh": {
        "rootLogin": "no",
        "passwordAuth": "no"
      }
    },
    "updates": {
      "maxPendingUpdates": 5,
      "unattendedUpgrades": false
    },
    "memory": {
      "swapEnabled": false
    },
    "time": {
      "ntpEnabled": true
    },
    "logs": {
      "solanaLogrotate": true
    }
  }
}
```

You can modify any of these values to match your specific system requirements.

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