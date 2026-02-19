#!/bin/bash

# Harmonic Auction Engine endpoints
AUCTION_HOSTS=(
    "ams.auction.harmonic.gg"
    "ewr.auction.harmonic.gg"
    "fra.auction.harmonic.gg"
    "lon.auction.harmonic.gg"
    "tyo.auction.harmonic.gg"
    "sgp.auction.harmonic.gg"
)

# Harmonic TPU Relayer endpoints
TPU_HOSTS=(
    "ams.tpu.harmonic.gg"
    "ewr.tpu.harmonic.gg"
    "fra.tpu.harmonic.gg"
    "lon.tpu.harmonic.gg"
    "tyo.tpu.harmonic.gg"
    "sgp.tpu.harmonic.gg"
)

# Harmonic Shred Receiver endpoints (IP:port - ping uses IP only)
SHRED_HOSTS=(
    "64.130.42.138"    # Amsterdam
    "198.73.57.238"    # Newark
    "64.130.32.204"    # Frankfurt
    "64.130.63.16"     # London
    "63.254.162.99"    # Tokyo
    "198.13.130.228"   # Singapore
)

SHRED_LABELS=(
    "64.130.42.138:8001 (Amsterdam)"
    "198.73.57.238:8001 (Newark)"
    "64.130.32.204:8001 (Frankfurt)"
    "64.130.63.16:8001 (London)"
    "63.254.162.99:8001 (Tokyo)"
    "198.13.130.228:8001 (Singapore)"
)

# Number of pings to send
COUNT=5

run_ping() {
    local host="$1"
    local label="${2:-$host}"

    stats=$(ping -c $COUNT "$host" 2>&1)

    if echo "$stats" | grep -q "100.0% packet loss\|100% packet loss\|Name or service not known\|Cannot resolve"; then
        printf "%-50s %-8s %-8s %-8s %-8s\n" "$label" "N/A" "N/A" "N/A" "100%"
        return
    fi

    loss="N/A"
    if echo "$stats" | grep -qE "[0-9.]+% packet loss"; then
        loss=$(echo "$stats" | grep -oE "[0-9.]+% packet loss" | grep -oE "^[0-9.]+")
    fi

    min="N/A"; avg="N/A"; max="N/A"
    rtt_line=$(echo "$stats" | grep "min/avg/max")
    if [ -n "$rtt_line" ]; then
        min=$(echo "$rtt_line" | sed -E 's|.* = ([0-9.]+)/([0-9.]+)/([0-9.]+).*|\1|')
        avg=$(echo "$rtt_line" | sed -E 's|.* = ([0-9.]+)/([0-9.]+)/([0-9.]+).*|\2|')
        max=$(echo "$rtt_line" | sed -E 's|.* = ([0-9.]+)/([0-9.]+)/([0-9.]+).*|\3|')
    fi

    printf "%-50s %-8s %-8s %-8s %-8s\n" "$label" "${min}ms" "${avg}ms" "${max}ms" "$loss%"
}

# --- Auction Engine ---
echo ""
echo "=== Harmonic Auction Engine ==="
printf "%-50s %-8s %-8s %-8s %-8s\n" "Host" "Min" "Avg" "Max" "Loss%"
printf "%s\n" "--------------------------------------------------------------------------------------------"
for host in "${AUCTION_HOSTS[@]}"; do
    run_ping "$host"
done

# --- TPU Relayer ---
echo ""
echo "=== Harmonic TPU Relayer ==="
printf "%-50s %-8s %-8s %-8s %-8s\n" "Host" "Min" "Avg" "Max" "Loss%"
printf "%s\n" "--------------------------------------------------------------------------------------------"
for host in "${TPU_HOSTS[@]}"; do
    run_ping "$host"
done

# --- Shred Receiver ---
echo ""
echo "=== Harmonic Shred Receiver ==="
printf "%-50s %-8s %-8s %-8s %-8s\n" "Host" "Min" "Avg" "Max" "Loss%"
printf "%s\n" "--------------------------------------------------------------------------------------------"
for i in "${!SHRED_HOSTS[@]}"; do
    run_ping "${SHRED_HOSTS[$i]}" "${SHRED_LABELS[$i]}"
done
