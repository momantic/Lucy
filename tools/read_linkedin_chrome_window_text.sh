#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMG="/tmp/lucy_linkedin_chrome_window.png"

BOUNDS="$(osascript -e 'tell application "Google Chrome" to get bounds of front window' | awk -F', ' '{print $1","$2","$3-$1","$4-$2}')"
echo "Chrome bounds: $BOUNDS" >&2

if ! /usr/sbin/screencapture -x -R "$BOUNDS" "$IMG"; then
    echo "Window capture failed; falling back to full screen." >&2
    /usr/sbin/screencapture -x "$IMG"
fi

swift "$SCRIPT_DIR/ocr_screen_text.swift" "$IMG" 2>/dev/null | grep -v "Unable to find a valid E5"
