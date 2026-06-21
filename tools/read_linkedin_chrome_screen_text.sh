#!/bin/zsh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMG="/tmp/lucy_linkedin_screen.png"

osascript -e 'tell application "Google Chrome" to activate'
sleep 2

screencapture -x "$IMG"
swift "$SCRIPT_DIR/ocr_screen_text.swift" "$IMG" 2>/dev/null
