#!/bin/bash

# Define hosts to ping
HOSTS=(
    "amsterdam.mainnet.bam.jito.wtf"
    "frankfurt.mainnet.bam.jito.wtf"
    "london.mainnet.bam.jito.wtf"
    "fny.mainnet.bam.jito.wtf"
    "slc.mainnet.bam.jito.wtf"
    "tokyo.mainnet.bam.jito.wtf"
    "singapore.mainnet.bam.jito.wtf"
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