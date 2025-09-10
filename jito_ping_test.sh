#!/bin/bash

# Define hosts to ping
HOSTS=(
    "mainnet.block-engine.jito.wtf"
    "amsterdam.mainnet.block-engine.jito.wtf"
    "frankfurt.mainnet.block-engine.jito.wtf"
    "london.mainnet.block-engine.jito.wtf"
    "ny.mainnet.block-engine.jito.wtf"
    "tokyo.mainnet.block-engine.jito.wtf"
    "slc.mainnet.block-engine.jito.wtf"
    "dublin.mainnet.block-engine.jito.wtf"
)

# Number of pings to send
COUNT=5

# Print header
printf "%-45s %-8s %-8s %-8s %-8s\n" "Host" "Min" "Avg" "Max" "Loss%"
printf "%s\n" "--------------------------------------------------------------------------------"

# Loop through each host
for host in "${HOSTS[@]}"; do
    # Get ping statistics
    stats=$(ping -c $COUNT $host | tail -1)
    
    # Extract ping times and packet loss
    if [[ $stats =~ ([0-9.]+)%\ packet\ loss ]]; then
        loss="${BASH_REMATCH[1]}"
    else
        loss="N/A"
    fi
    
    if [[ $stats =~ min/avg/max.*\ =\ ([0-9.]+)/([0-9.]+)/([0-9.]+) ]]; then
        min="${BASH_REMATCH[1]}"
        avg="${BASH_REMATCH[2]}"
        max="${BASH_REMATCH[3]}"
    else
        min="N/A"
        avg="N/A"
        max="N/A"
    fi
    
    # Print results in a formatted way
    printf "%-45s %-8s %-8s %-8s %-8s\n" "$host" "${min}ms" "${avg}ms" "${max}ms" "$loss%"
done