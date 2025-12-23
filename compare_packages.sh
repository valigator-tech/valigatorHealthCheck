#!/bin/bash
#
# Compare installed APT packages between local and remote server
# Usage: ./compare_packages.sh remote-server
# Note: Connects as sol@remote using local sol user's SSH keys
#

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <remote-server>"
    echo "Example: $0 192.168.1.100"
    exit 1
fi

REMOTE_HOST="sol@$1"
LOCAL_TMP=$(mktemp)
REMOTE_TMP=$(mktemp)

cleanup() {
    rm -f "$LOCAL_TMP" "$REMOTE_TMP"
}
trap cleanup EXIT

echo "Checking for auto-removable packages on local system..."
AUTOREMOVE=$(apt-get --dry-run autoremove 2>/dev/null | grep -oP '^\s+\K\S+' | tr '\n' ' ')
echo ""
echo "=========================================="
echo "LOCAL PACKAGES NO LONGER NEEDED"
echo "(can be removed with: apt autoremove)"
echo "=========================================="
if [[ -z "$AUTOREMOVE" ]]; then
    echo "(none)"
else
    echo "$AUTOREMOVE"
fi

echo ""
echo "Scanning for potentially unnecessary packages..."
echo ""
echo "=========================================="
echo "POTENTIAL BLOAT (review before removing)"
echo "=========================================="

# Get all installed packages
ALL_PKGS=$(dpkg-query -W -f='${Package}\n')

# Development packages (usually not needed on production)
DEV_PKGS=$(echo "$ALL_PKGS" | grep -E '\-(dev|devel)$' | tr '\n' ' ' || true)
if [[ -n "$DEV_PKGS" ]]; then
    echo ""
    echo "[Development packages]"
    echo "$DEV_PKGS"
fi

# Documentation packages
DOC_PKGS=$(echo "$ALL_PKGS" | grep -E '\-doc$|^doc\-' | tr '\n' ' ' || true)
if [[ -n "$DOC_PKGS" ]]; then
    echo ""
    echo "[Documentation]"
    echo "$DOC_PKGS"
fi

# GUI/Desktop/X11 related
GUI_PKGS=$(echo "$ALL_PKGS" | grep -iE '^x11|^libx11|^libgtk|^libqt|^gnome|^kde|^wayland|^libwayland|^xorg|^xserver' | tr '\n' ' ' || true)
if [[ -n "$GUI_PKGS" ]]; then
    echo ""
    echo "[GUI/Desktop/X11]"
    echo "$GUI_PKGS"
fi

# Build tools
BUILD_PKGS=$(echo "$ALL_PKGS" | grep -E '^gcc$|^gcc\-[0-9]+$|^g\+\+|^make$|^build\-essential$|^cmake$|^autoconf$|^automake$|^libtool$' | tr '\n' ' ' || true)
if [[ -n "$BUILD_PKGS" ]]; then
    echo ""
    echo "[Build tools]"
    echo "$BUILD_PKGS"
fi

# Potentially unused language runtimes
LANG_PKGS=$(echo "$ALL_PKGS" | grep -E '^ruby[0-9]|^php[0-9]|^perl$|^tcl[0-9]|^lua[0-9]' | tr '\n' ' ' || true)
if [[ -n "$LANG_PKGS" ]]; then
    echo ""
    echo "[Language runtimes - verify if needed]"
    echo "$LANG_PKGS"
fi

# Games, fonts, sound
MISC_PKGS=$(echo "$ALL_PKGS" | grep -iE '^game|^fonts\-|^pulseaudio|^alsa\-|^sound' | tr '\n' ' ' || true)
if [[ -n "$MISC_PKGS" ]]; then
    echo ""
    echo "[Games/Fonts/Sound]"
    echo "$MISC_PKGS"
fi

# Man pages
MAN_PKGS=$(echo "$ALL_PKGS" | grep -E '^man\-db$|^manpages' | tr '\n' ' ' || true)
if [[ -n "$MAN_PKGS" ]]; then
    echo ""
    echo "[Man pages]"
    echo "$MAN_PKGS"
fi

# Check if anything was found
if [[ -z "$DEV_PKGS" && -z "$DOC_PKGS" && -z "$GUI_PKGS" && -z "$BUILD_PKGS" && -z "$LANG_PKGS" && -z "$MISC_PKGS" && -z "$MAN_PKGS" ]]; then
    echo "(none detected)"
fi

echo ""
echo "Gathering local packages..."
dpkg-query -W -f='${Package}\n' | sort -u > "$LOCAL_TMP"
LOCAL_COUNT=$(wc -l < "$LOCAL_TMP")
echo "  Found $LOCAL_COUNT packages locally"

echo "Gathering remote packages from $REMOTE_HOST..."
sudo -u sol ssh "$REMOTE_HOST" "dpkg-query -W -f='\${Package}\n'" | sort -u > "$REMOTE_TMP"
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
