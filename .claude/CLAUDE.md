# Valigator Health Check - Project Documentation

## Project Overview

This repository contains system health check and utility scripts for Solana validator infrastructure. The primary tool is a comprehensive health check script that verifies optimal system configuration for high-performance Solana validator nodes.

## Working Guidelines

**IMPORTANT**: When working on this project:
- Always create a git commit after making changes
- Do not guess at functionality if confidence is low - ask clarifying questions instead
- This is production infrastructure tooling; accuracy is critical

---

## Scripts

### health_check.sh

**Purpose**: Comprehensive system health check for Linux servers optimized for Solana validator operation.

**Location**: `/health_check.sh`

**Usage**:
```bash
sudo ./health_check.sh                    # Basic run
sudo ./health_check.sh -q                 # Quiet mode (summary only)
sudo ./health_check.sh -c /path/to/config # Custom config file
sudo ./health_check.sh -h                 # Help
```

**Dependencies**:
- `jq` - Required for parsing JSON configuration
- `ethtool` - Required for NIC ring buffer checks
- `nvme-cli` - Required for NVMe wear level checks
- Root/sudo access for most checks

**Configuration**: Uses `config.json` (or `local_config.json` if present) in the script directory. Custom config can be specified with `-c` flag.

**Checks Performed** (all configurable via `checksToRun` in config):

| Check | Config Key | Description |
|-------|------------|-------------|
| Sysctl Parameters | `sysctlParams` | TCP buffers, kernel optimization, VM tuning, Solana-specific network settings |
| CPU Governor | `cpuGovernor` | Verifies all CPU cores use "performance" governor |
| CPU Boost | `cpuBoost` | Ensures CPU turbo/boost is enabled |
| CPU Driver | `cpuDriver` | Checks for p-state driver (Intel or AMD) |
| C-States | `cstatesDisabled` | Verifies CPU C-states are disabled for low latency |
| AMD P-State EPP | `amdPstateEpp` | Checks AMD energy performance preference is set to "performance" |
| Isolated CPUs | `isolatedCpus` | Reports on CPU core isolation (informational) |
| CPU Power Limits | `cpuPowerLimits` | Checks Intel RAPL power limits |
| Fail2ban | `fail2ban` | Verifies fail2ban is installed, enabled, and running |
| Swap Status | `swapStatus` | Confirms swap is disabled (configurable) |
| Package Updates | `packageUpdates` | Checks pending updates against threshold (default: 5) |
| NTP Sync | `ntpSync` | Verifies systemd-timesyncd is active |
| Timezone | `timezoneUtc` | Confirms system timezone is UTC |
| SSH Config | `sshConfig` | Validates SSH security (root login disabled, key-only auth) |
| Required Packages | `requiredPackages` | Checks for rsyslog and ufw packages |
| Solana Logrotate | `solanaLogrotate` | Verifies logrotate config exists for Solana logs |
| Unattended Upgrades | `unattendedUpgrades` | Confirms automatic updates are disabled |
| Reboot Status | `rebootStatus` | Checks if system requires a reboot |
| NIC Ring Buffers | `nicRingBuffers` | Verifies network interface ring buffers are at maximum |
| Ethtool Service | `ethtoolService` | Checks ethtool-ring-buffers.service is active |
| NVMe Wear | `nvmeWear` | Monitors NVMe drive wear levels against threshold |

**NIC Exclusion**: Network interfaces can be excluded from ring buffer checks via config:
```json
"network": {
  "excludedNics": ["eno1", "enp0s31f6"]
}
```

**Exit Codes**:
- `0` - All checks passed
- `1` - One or more checks failed

---

### jito_ping_test.sh

**Purpose**: Latency benchmarking tool for Jito block engine endpoints. Used to determine optimal datacenter/region placement for Solana validators based on network latency to Jito MEV infrastructure.

**Location**: `/jito_ping_test.sh`

**Usage**:
```bash
./jito_ping_test.sh
```

**Hosts Tested**:
- mainnet.block-engine.jito.wtf (global)
- amsterdam.mainnet.block-engine.jito.wtf
- dublin.mainnet.block-engine.jito.wtf
- frankfurt.mainnet.block-engine.jito.wtf
- london.mainnet.block-engine.jito.wtf
- ny.mainnet.block-engine.jito.wtf
- slc.mainnet.block-engine.jito.wtf
- singapore.mainnet.block-engine.jito.wtf
- tokyo.mainnet.block-engine.jito.wtf

**Output**: Tabular format showing Min/Avg/Max latency and packet loss percentage for each endpoint.

**Dependencies**: `ping` command

---

### bam_ping_test.sh

**Purpose**: Latency benchmarking tool for Jito BAM (Block Auction Marketplace) endpoints. Used alongside jito_ping_test.sh to evaluate full Jito infrastructure connectivity.

**Location**: `/bam_ping_test.sh`

**Usage**:
```bash
./bam_ping_test.sh
```

**Hosts Tested**:
- amsterdam.mainnet.bam.jito.wtf
- frankfurt.mainnet.bam.jito.wtf
- london.mainnet.bam.jito.wtf
- ny.mainnet.bam.jito.wtf
- slc.mainnet.bam.jito.wtf
- tokyo.mainnet.bam.jito.wtf
- singapore.mainnet.bam.jito.wtf

**Output**: Tabular format showing Min/Avg/Max latency and packet loss percentage for each endpoint.

**Dependencies**: `ping` command

---

### harmonic_ping_test.sh

**Purpose**: Latency benchmarking tool for Harmonic auction endpoints. Used to evaluate network latency to Harmonic MEV infrastructure for validator placement decisions.

**Location**: `/harmonic_ping_test.sh`

**Usage**:
```bash
./harmonic_ping_test.sh
```

**Hosts Tested**:
- ams.auction.harmonic.gg (Amsterdam)
- ewr.auction.harmonic.gg (Newark/EWR)

**Output**: Tabular format showing Min/Avg/Max latency and packet loss percentage for each endpoint.

**Dependencies**: `ping` command

---

### compare_packages.sh

**Purpose**: Compares installed APT packages between a local machine and a remote server. Used to ensure consistency between Solana validator servers.

**Location**: `/compare_packages.sh`

**Usage**:
```bash
./compare_packages.sh user@remote-server
./compare_packages.sh root@192.168.1.100
```

**Output**:
1. Count of packages on each system
2. Packages on local but not on remote (install these on remote to match)
3. Packages on remote but not on local (install these on local to match)

**Dependencies**:
- `dpkg-query` - Debian/Ubuntu package query tool
- `ssh` - SSH access to remote server
- Remote server must also be Debian/Ubuntu based

**Notes**:
- Uses temporary files that are cleaned up on exit
- Requires SSH key-based authentication (or will prompt for password)

---

## Configuration Files

### config.json

Main configuration file for health_check.sh. Contains:
- `checksToRun`: Enable/disable individual checks
- `systemChecks`: Expected values for system settings
- `sysctlChecks`: Expected sysctl parameter values organized by category

### local_config.json

Optional local override configuration. If present in the script directory, it takes precedence over config.json. Useful for machine-specific settings without modifying the main config.

**Note**: local_config.json is in .gitignore and should not be committed.

---

## Directory Structure

```
valigatorHealthCheck/
├── .claude/
│   ├── CLAUDE.md          # This documentation
│   ├── settings.json      # Claude Code settings
│   └── settings.local.json # Local Claude Code settings
├── backups/               # Backup copies of scripts and configs
├── health_check.sh        # Main health check script
├── jito_ping_test.sh      # Jito block engine latency test
├── bam_ping_test.sh       # Jito BAM latency test
├── harmonic_ping_test.sh  # Harmonic auction latency test
├── compare_packages.sh    # Package comparison utility
├── config.json            # Default configuration
├── README.md              # User-facing documentation
└── .gitignore
```
