#!/usr/bin/env bash
# validator_diag.sh — Non-impacting diagnostic report for Solana validators.
#
# Read-only: gathers data, performs no writes, no service restarts, no config changes.
# One ~2-second sleep for IRQ delta sampling. Otherwise instantaneous.
#
# Run as root (or with sudo) for full coverage. Without root, audit state and a few
# /proc/<pid> reads may be skipped — the script will note this and continue.
#
# Usage:  sudo bash validator_diag.sh
#         sudo bash validator_diag.sh | tee val-XX-diag-$(date +%F).txt
#
# Exit 0 always; this is a report, not a check.

# ansible val-46 -m script -a "validator_diag.sh" --become

set -u

# ----- output helpers -----
if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; RST=$'\033[0m'
else
    BOLD=''; DIM=''; RED=''; YEL=''; GRN=''; RST=''
fi
section() { printf '\n%s=== %s ===%s\n' "$BOLD" "$1" "$RST"; }
note()    { printf '  %s%s%s %s\n' "$DIM" '--' "$RST" "$*"; }
ok()      { printf '  [%sOK%s]   %s\n' "$GRN" "$RST" "$*"; }
warn()    { printf '  [%sWARN%s] %s\n' "$YEL" "$RST" "$*"; }
err()     { printf '  [%s!!%s]   %s\n' "$RED" "$RST" "$*"; }
kv()      { printf '    %-32s %s\n' "$1" "$2"; }
have()    { command -v "$1" >/dev/null 2>&1; }
is_root() { [[ "$(id -u)" -eq 0 ]]; }

# Strip non-numeric tokens from a kernel-cmdline cpu list value.
# "domain,2,26" -> "2,26";  "managed_irq,nohz,2,26" -> "2,26";  "cpu:0-1,3-25" -> "0-1,3-25"
clean_cpu_list() {
    local raw=$1; raw=${raw#cpu:}; local out=""
    IFS=',' read -ra parts <<< "$raw"
    for p in "${parts[@]}"; do
        [[ "$p" =~ ^[0-9]+(-[0-9]+)?$ ]] && out="${out}${out:+,}$p"
    done
    echo "$out"
}

# Expand "0-3,5,7-8" to "0 1 2 3 5 7 8"
expand_cpus() {
    local list=$1; [[ -z "$list" ]] && return
    local out=()
    IFS=',' read -ra parts <<< "$list"
    for p in "${parts[@]}"; do
        if [[ "$p" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            for ((i=${BASH_REMATCH[1]}; i<=${BASH_REMATCH[2]}; i++)); do out+=("$i"); done
        elif [[ "$p" =~ ^[0-9]+$ ]]; then
            out+=("$p")
        fi
    done
    echo "${out[@]}"
}

in_set() { local n=$1 h=" $2 "; [[ "$h" == *" $n "* ]]; }

# ============================================================================
section "Host"
# ============================================================================
kv "hostname" "$(hostname)"
kv "kernel"   "$(uname -r)"
kv "uptime"   "$(uptime -p 2>/dev/null || uptime)"
[[ -r /etc/os-release ]] && ( . /etc/os-release; kv "os" "$PRETTY_NAME" )
is_root || warn "not running as root — audit state, some /proc reads may be skipped"

# ============================================================================
section "CPU & topology"
# ============================================================================
if have lscpu; then
    lscpu | awk -F: '
        /^Model name|^Socket\(s\)|^Core\(s\) per socket|^Thread\(s\) per core|^CPU\(s\):|^NUMA node\(s\)|^CPU max MHz|^CPU min MHz/ {
            gsub(/^ +/,"",$2); printf "    %-32s %s\n", $1, $2 }'
fi

CMDLINE=$(cat /proc/cmdline)
ISOLCPUS_RAW=$(grep -oE 'isolcpus=[^ ]+'    <<<"$CMDLINE" | sed 's/^isolcpus=//'    || true)
NOHZFULL_RAW=$(grep -oE 'nohz_full=[^ ]+'   <<<"$CMDLINE" | sed 's/^nohz_full=//'   || true)
RCUNOCBS_RAW=$(grep -oE 'rcu_nocbs=[^ ]+'   <<<"$CMDLINE" | sed 's/^rcu_nocbs=//'   || true)
IRQAFF_RAW=$(grep   -oE 'irqaffinity=[^ ]+' <<<"$CMDLINE" | sed 's/^irqaffinity=//' || true)
HOUSEKP_RAW=$(grep  -oE 'housekeeping=[^ ]+'<<<"$CMDLINE" | sed 's/^housekeeping=//' || true)

ISO_LIST=$(clean_cpu_list   "${ISOLCPUS_RAW:-}")
NOHZ_LIST=$(clean_cpu_list  "${NOHZFULL_RAW:-}")
RCU_LIST=$(clean_cpu_list   "${RCUNOCBS_RAW:-}")
IRQ_LIST=$(clean_cpu_list   "${IRQAFF_RAW:-}")
HOUSE_LIST=$(clean_cpu_list "${HOUSEKP_RAW:-}")

note "isolation params (parsed from /proc/cmdline):"
kv "isolcpus"     "${ISOLCPUS_RAW:-(unset)}    -> [$ISO_LIST]"
kv "nohz_full"    "${NOHZFULL_RAW:-(unset)}    -> [$NOHZ_LIST]"
kv "rcu_nocbs"    "${RCUNOCBS_RAW:-(unset)}    -> [$RCU_LIST]"
kv "irqaffinity"  "${IRQAFF_RAW:-(unset)}      -> [$IRQ_LIST]"
kv "housekeeping" "${HOUSEKP_RAW:-(unset)}     -> [$HOUSE_LIST]"

ISO_CPUS=$(expand_cpus "$ISO_LIST")
HOUSE_CPUS=$(expand_cpus "$HOUSE_LIST")
NPROC=$(nproc 2>/dev/null || echo 0)

# Coverage check: every logical CPU should be in either isolated or housekeeping
if [[ -n "$HOUSE_LIST" && -n "$ISO_LIST" && "$NPROC" -gt 0 ]]; then
    UNCOVERED=()
    for ((c=0; c<NPROC; c++)); do
        if ! in_set "$c" "$ISO_CPUS" && ! in_set "$c" "$HOUSE_CPUS"; then
            UNCOVERED+=("$c")
        fi
    done
    if (( ${#UNCOVERED[@]} > 0 )); then
        warn "CPUs not in isolcpus and not in housekeeping: ${UNCOVERED[*]}"
    else
        ok "all $NPROC logical CPUs are in either isolated or housekeeping pool"
    fi
fi

# SMT sibling sanity for isolated cores
if [[ -n "$ISO_CPUS" ]]; then
    note "SMT sibling analysis for isolated cores:"
    for c in $ISO_CPUS; do
        sib_file="/sys/devices/system/cpu/cpu${c}/topology/thread_siblings_list"
        if [[ -r "$sib_file" ]]; then
            sibs=$(<"$sib_file")
            cid=$(<"/sys/devices/system/cpu/cpu${c}/topology/core_id" 2>/dev/null || echo '?')
            pkg=$(<"/sys/devices/system/cpu/cpu${c}/topology/physical_package_id" 2>/dev/null || echo '?')
            kv "cpu${c}" "siblings=$sibs  core_id=$cid  pkg=$pkg"
            for s in $(tr ',' ' ' <<<"$sibs"); do
                [[ "$s" == "$c" ]] && continue
                if in_set "$s" "$HOUSE_CPUS"; then
                    err "isolated cpu${c}'s SMT sibling cpu${s} is in housekeeping pool — they share L1/L2; housekeeping work will leak jitter into the isolated tile"
                fi
                if in_set "$s" "$ISO_CPUS"; then
                    ok "cpu${c}'s SMT sibling cpu${s} is also isolated"
                fi
            done
        fi
    done
fi

# ============================================================================
section "CPU frequency / idle"
# ============================================================================
if [[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
    govs=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort -u | tr '\n' ' ')
    kv "governors (unique)" "$govs"
    case "$govs" in
        *"powersave"*|*"ondemand"*|*"conservative"*)
            warn "non-performance governor present — adds ramp latency on idle->busy" ;;
        *"performance"*|*"schedutil"*)
            ok "governor looks reasonable for a validator" ;;
    esac
fi
[[ -r /sys/devices/system/cpu/amd_pstate/status   ]] && kv "amd_pstate status"   "$(cat /sys/devices/system/cpu/amd_pstate/status)"
[[ -r /sys/devices/system/cpu/intel_pstate/status ]] && kv "intel_pstate status" "$(cat /sys/devices/system/cpu/intel_pstate/status)"

if compgen -G "/sys/devices/system/cpu/cpu0/cpuidle/state*/disable" > /dev/null; then
    note "C-states on CPU 0 (lower exit_latency = less jitter when entered):"
    for s in /sys/devices/system/cpu/cpu0/cpuidle/state*; do
        printf "    %-12s disabled=%s  exit_latency=%5s us\n" \
            "$(<"$s/name")" "$(<"$s/disable")" "$(<"$s/latency")"
    done
fi

# ============================================================================
section "Audit subsystem"
# ============================================================================
if have auditctl && is_root; then
    auditctl -s 2>/dev/null | sed 's/^/    /'
    rules_file=$(mktemp)
    auditctl -l 2>/dev/null > "$rules_file"
    rule_count=$(grep -cv '^[[:space:]]*$' "$rules_file" || echo 0)
    kv "rule count" "$rule_count"

    lost=$(auditctl -s 2>/dev/null | awk '$1=="lost"{print $2}')
    backlog=$(auditctl -s 2>/dev/null | awk '$1=="backlog"{print $2}')
    [[ "${lost:-0}"    -gt 0   ]] && warn "audit lost=${lost} (kernel had to drop events since boot)"
    [[ "${backlog:-0}" -gt 100 ]] && warn "audit backlog=${backlog} non-trivial — userspace slow draining"
    [[ "${lost:-0}" -eq 0 && "${backlog:-0}" -lt 100 ]] && ok "audit not dropping or backlogged"

    if grep -qE -- '-S[[:space:]]+(send|recv|sendto|sendmsg|recvfrom|recvmsg|sendmmsg|recvmmsg|connect|accept|socket)' "$rules_file"; then
        err "audit rules match network syscalls — likely shred-path overhead:"
        grep -E -- '-S[[:space:]]+(send|recv|connect|accept|socket)' "$rules_file" | sed 's/^/        /'
    else
        ok "no audit rules touch network syscalls"
    fi
    rm -f "$rules_file"
elif have auditctl; then
    note "auditctl exists but requires root — rerun with sudo"
fi

# ============================================================================
section "Network sysctls (UDP-relevant)"
# ============================================================================
for k in net.core.rmem_default net.core.rmem_max \
         net.core.wmem_default net.core.wmem_max \
         net.core.netdev_max_backlog net.core.somaxconn \
         net.ipv4.udp_rmem_min net.ipv4.udp_wmem_min \
         net.ipv4.ip_local_port_range; do
    kv "$k" "$(sysctl -n "$k" 2>/dev/null || echo "(unset)")"
done

RMEM_MAX=$(sysctl -n net.core.rmem_max 2>/dev/null || echo 0)
(( RMEM_MAX < 134217728 )) && warn "net.core.rmem_max=$RMEM_MAX < 128 MiB (Solana docs recommend 134217728)"

# ----- Validator process discovery -----
VAL_PID=""; VAL_NAME=""
for pat in agave-validator solana-validator fdctl firedancer; do
    p=$(pgrep -x "$pat" 2>/dev/null | head -n1 || true)
    [[ -z "$p" ]] && p=$(pgrep -f -- "$pat" 2>/dev/null | head -n1 || true)
    if [[ -n "$p" ]]; then VAL_PID="$p"; VAL_NAME="$pat"; break; fi
done

# ----- Port range overlap with --dynamic-port-range -----
LPR=$(sysctl -n net.ipv4.ip_local_port_range 2>/dev/null)
LPR_LO=$(awk '{print $1}' <<<"$LPR"); LPR_HI=$(awk '{print $2}' <<<"$LPR")

DYN_LO=8000; DYN_HI=10000; DYN_SRC="default"
if [[ -n "$VAL_PID" && -r "/proc/$VAL_PID/cmdline" ]]; then
    VAL_CMDLINE=$(tr '\0' ' ' < "/proc/$VAL_PID/cmdline")
    DYN=$(grep -oE -- '--dynamic-port-range[= ][0-9]+-[0-9]+' <<<"$VAL_CMDLINE" | grep -oE '[0-9]+-[0-9]+' || true)
    if [[ -n "$DYN" ]]; then DYN_LO=${DYN%-*}; DYN_HI=${DYN#*-}; DYN_SRC="--dynamic-port-range"; fi
fi
kv "validator port range ($DYN_SRC)" "$DYN_LO-$DYN_HI"
if (( LPR_LO <= DYN_HI && DYN_LO <= LPR_HI )); then
    err "OVERLAP: ip_local_port_range ($LPR) overlaps validator port range ($DYN_LO-$DYN_HI). Same class of bug as val-55."
else
    ok "ip_local_port_range and validator port range do not overlap"
fi

# ============================================================================
section "UDP / socket counters (since boot)"
# ============================================================================
if have netstat; then
    netstat -su 2>/dev/null | awk '
        /^Udp:|^Udp6:|^IpExt:/ {section=$0; print "  "section; next}
        section ~ /Udp/ && /(errors|dropped|RcvbufErrors|SndbufErrors|InCsumErrors|InErrors)/ {print "    "$0}
        section ~ /IpExt/ && /Octets/ {print "    "$0}'
fi

if have ss; then
    note "UDP sockets with non-empty Recv-Q (top 10):"
    ss -Hunmp 2>/dev/null | awk 'NF>=4 && $2+0 > 0' | sort -k2 -n -r | head -n 10 \
        | awk '{printf "    %-8s %-12s %-25s %-25s %s\n", $1, $2"/"$3, $4, $5, $6}'
fi

# ============================================================================
section "NIC stats (per physical interface)"
# ============================================================================
NIC_LIST=()
for iface in $(ls /sys/class/net 2>/dev/null); do
    [[ "$iface" == "lo" ]] && continue
    [[ -e "/sys/class/net/$iface/device" ]] || continue
    NIC_LIST+=("$iface")
done

for iface in "${NIC_LIST[@]}"; do
    note "interface: $iface"
    if have ethtool; then
        speed=$(ethtool "$iface" 2>/dev/null | awk -F: '/Speed:/{gsub(/^ +/,"",$2); print $2}')
        link=$(ethtool "$iface"  2>/dev/null | awk -F: '/Link detected:/{gsub(/^ +/,"",$2); print $2}')
        kv "  speed/link" "${speed:-?} / link=${link:-?}"

        rg=$(ethtool -g "$iface" 2>/dev/null | awk '
            /Current hardware settings/{cur=1; next}
            cur && /^(RX|TX):/ {gsub(/:/,"",$1); printf "%s=%s ",$1,$2}')
        [[ -n "$rg" ]] && kv "  ring (current)" "$rg"

        echo "    error/drop counters (non-zero only):"
        any=0
        while IFS= read -r line; do
            n=$(awk '{print $NF+0}' <<<"$line")
            if (( n > 0 )); then printf "      %s\n" "$line"; any=1; fi
        done < <(ethtool -S "$iface" 2>/dev/null | grep -iE 'drop|discard|miss|error|fifo|overrun|crc|no_buff|alloc_fail')
        (( any == 0 )) && printf "      (none)\n"
    else
        note "(ethtool not installed)"
    fi
done

# ============================================================================
section "NIC IRQ affinity (delta over ~2s)"
# ============================================================================
if [[ -r /proc/interrupts && -n "$ISO_LIST" ]]; then
    snap1=$(mktemp); snap2=$(mktemp)
    cp /proc/interrupts "$snap1"; sleep 2; cp /proc/interrupts "$snap2"

    awk -v iso="$(echo "$ISO_CPUS" | tr ' ' ',')" '
        BEGIN {
            n=split(iso, a, ",")
            for (i=1; i<=n; i++) iso_set[a[i]+0]=1
        }
        NR==FNR {
            if (FNR==1) { for (i=1; i<=NF; i++) if ($i ~ /^CPU[0-9]+$/) { hdr[i]=substr($i,4)+0; ncpu=i }; next }
            if ($1 ~ /:$/) { irq=$1; for (i=1; i<=ncpu; i++) before[irq "@" hdr[i]] = $(i+1)+0 }
            next
        }
        FNR==1 { next }
        /^[[:space:]]*[0-9]+:/ {
            irq=$1; desc=""
            for (j=ncpu+2; j<=NF; j++) desc = desc " " $j
            if (desc !~ /(eth|ens|enp|eno|mlx|i40e|ice|bnxt|virtio_net|igb|ixgbe)/) next
            total_iso=0; cpus_hit=""
            for (i=1; i<=ncpu; i++) {
                cpu=hdr[i]
                if (cpu in iso_set) {
                    d = $(i+1) + 0 - before[irq "@" cpu]
                    if (d > 0) { total_iso += d; cpus_hit = cpus_hit " cpu" cpu "(+" d ")" }
                }
            }
            if (total_iso > 0) printf "  [WARN] IRQ %s%s: %d hits on isolated CPUs in 2s ->%s\n", irq, desc, total_iso, cpus_hit
        }
    ' "$snap1" "$snap2"

    rm -f "$snap1" "$snap2"
    note "(no [WARN] lines above means no NIC IRQs fired on isolated cores during the 2s window)"
else
    note "skipped (no isolated CPUs detected, or /proc/interrupts unreadable)"
fi

# ============================================================================
section "Time sync"
# ============================================================================
if have chronyc; then
    note "chronyc tracking:"
    chronyc tracking 2>/dev/null | sed 's/^/    /'
    note "chronyc sources (-n):"
    chronyc -n sources 2>/dev/null | sed 's/^/    /'
elif have timedatectl; then
    timedatectl status 2>/dev/null | sed 's/^/    /'
fi
kv "clocksource" "$(cat /sys/devices/system/clocksource/clocksource0/current_clocksource 2>/dev/null || echo '?')"
kv "available"   "$(cat /sys/devices/system/clocksource/clocksource0/available_clocksource 2>/dev/null || echo '?')"

# ============================================================================
section "Validator process"
# ============================================================================
if [[ -n "$VAL_PID" ]]; then
    kv "binary" "$VAL_NAME"
    kv "pid"    "$VAL_PID"
    if [[ -r "/proc/$VAL_PID/status" ]]; then
        cpus_allowed=$(awk '/^Cpus_allowed_list:/{print $2}' "/proc/$VAL_PID/status")
        kv "Cpus_allowed_list" "$cpus_allowed"
        kv "voluntary_ctxt"    "$(awk '/^voluntary_ctxt_switches:/{print $2}'    "/proc/$VAL_PID/status")"
        kv "nonvoluntary_ctxt" "$(awk '/^nonvoluntary_ctxt_switches:/{print $2}' "/proc/$VAL_PID/status")"
        if [[ -n "$ISO_LIST" ]]; then
            for c in $ISO_CPUS; do
                if ! grep -qwE "(^|[,-])$c([,-]|$)" <<<"$cpus_allowed"; then
                    warn "isolated cpu${c} not in validator's Cpus_allowed_list ($cpus_allowed)"
                fi
            done
        fi
    fi

    note "top threads by CPU (one snapshot, may not catch hot tiles):"
    ps -L -o pid,tid,psr,pcpu,comm -p "$VAL_PID" 2>/dev/null | sort -k4 -n -r | head -n 12 | sed 's/^/    /'

    if have systemctl; then
        unit=$(systemctl status "$VAL_PID" 2>/dev/null | awk 'NR==1{print $2}')
        if [[ -n "$unit" && "$unit" != *"not-found"* ]]; then
            kv "systemd unit" "$unit"
            cpuaff=$(systemctl show -p CPUAffinity "$unit" 2>/dev/null | sed 's/^CPUAffinity=//')
            kv "  CPUAffinity" "${cpuaff:-(none)}"
        fi
    fi
else
    note "no agave/solana/firedancer validator process found"
fi

# ============================================================================
section "Memory / THP / NUMA"
# ============================================================================
[[ -r /sys/kernel/mm/transparent_hugepage/enabled ]] && kv "THP enabled" "$(cat /sys/kernel/mm/transparent_hugepage/enabled)"
[[ -r /sys/kernel/mm/transparent_hugepage/defrag  ]] && kv "THP defrag"  "$(cat /sys/kernel/mm/transparent_hugepage/defrag)"
kv "vm.swappiness"    "$(sysctl -n vm.swappiness)"
kv "vm.max_map_count" "$(sysctl -n vm.max_map_count)"
kv "fs.nr_open"       "$(sysctl -n fs.nr_open 2>/dev/null || echo '?')"

if have numactl; then
    note "numactl --hardware:"
    numactl --hardware 2>/dev/null | sed 's/^/    /'
fi

# ============================================================================
section "Done"
# ============================================================================
note "Read-only report complete."
is_root || note "Re-run with sudo for audit subsystem state and full /proc coverage."