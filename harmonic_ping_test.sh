#!/bin/bash

# Harmonic Auction Engine endpoints
AUCTION_HOSTS=(
    "ams.auction.harmonic.gg"
    "ewr.auction.harmonic.gg"
    "fra.auction.harmonic.gg"
    "lon.auction.harmonic.gg"
    "tyo.auction.harmonic.gg"
    "sgp.auction.harmonic.gg"
    "slc.auction.harmonic.gg"
)

# Harmonic TPU Relayer endpoints
TPU_HOSTS=(
    "ams.tpu.harmonic.gg"
    "ewr.tpu.harmonic.gg"
    "fra.tpu.harmonic.gg"
    "lon.tpu.harmonic.gg"
    "tyo.tpu.harmonic.gg"
    "sgp.tpu.harmonic.gg"
    "slc.tpu.harmonic.gg"
)

# Harmonic Shred Receiver endpoints (IP:port - ping uses IP only)
SHRED_HOSTS=(
    "63.254.166.232"   # Amsterdam
    "64.130.45.196"    # Newark
    "198.13.140.105"   # Frankfurt
    "64.130.46.242"    # London
    "198.13.133.200"   # Tokyo
    "198.13.130.10"    # Singapore
    "64.130.33.192"    # Salt Lake City
)

SHRED_LABELS=(
    "63.254.166.232:8001 (Amsterdam)"
    "64.130.45.196:8001 (Newark)"
    "198.13.140.105:8001 (Frankfurt)"
    "64.130.46.242:8001 (London)"
    "198.13.133.200:8001 (Tokyo)"
    "198.13.130.10:8001 (Singapore)"
    "64.130.33.192:8001 (Salt Lake City)"
)

# Number of pings to send
COUNT=5
FULL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --full|-f)
            FULL=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--full|-f]"
            echo "  Default: ping Auction Engine endpoints only"
            echo "  --full, -f: ping all endpoints (Auction + TPU Relayer + Shred Receiver)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--full|-f]"
            exit 1
            ;;
    esac
done

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

if [ "$FULL" = true ]; then
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
fi
