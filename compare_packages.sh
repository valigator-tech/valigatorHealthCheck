#!/bin/bash
#
# Compare installed APT packages between local and remote server
# Usage: ./compare_packages.sh user@remote-server
#

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <user@remote-server>"
    echo "Example: $0 root@192.168.1.100"
    exit 1
fi

REMOTE_HOST="$1"
LOCAL_TMP=$(mktemp)
REMOTE_TMP=$(mktemp)

cleanup() {
    rm -f "$LOCAL_TMP" "$REMOTE_TMP"
}
trap cleanup EXIT

echo "Gathering local packages..."
dpkg-query -W -f='${Package}\n' | sort -u > "$LOCAL_TMP"
LOCAL_COUNT=$(wc -l < "$LOCAL_TMP")
echo "  Found $LOCAL_COUNT packages locally"

echo "Gathering remote packages from $REMOTE_HOST..."
ssh "$REMOTE_HOST" "dpkg-query -W -f='\${Package}\n'" | sort -u > "$REMOTE_TMP"
REMOTE_COUNT=$(wc -l < "$REMOTE_TMP")
echo "  Found $REMOTE_COUNT packages on remote"

echo ""
echo "=========================================="
echo "PACKAGES ON LOCAL BUT NOT ON REMOTE"
echo "(install these on remote to match local)"
echo "=========================================="
LOCAL_ONLY=$(comm -23 "$LOCAL_TMP" "$REMOTE_TMP" | tr '\n' ' ')
if [[ -z "$LOCAL_ONLY" ]]; then
    echo "(none)"
else
    echo "$LOCAL_ONLY"
fi

echo ""
echo "=========================================="
echo "PACKAGES ON REMOTE BUT NOT ON LOCAL"
echo "(install these on local to match remote)"
echo "=========================================="
REMOTE_ONLY=$(comm -13 "$LOCAL_TMP" "$REMOTE_TMP" | tr '\n' ' ')
if [[ -z "$REMOTE_ONLY" ]]; then
    echo "(none)"
else
    echo "$REMOTE_ONLY"
fi

echo ""
