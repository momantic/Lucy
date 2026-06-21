#!/bin/zsh
# Captures screen then OCRs it.
# Usage:
# tools/read_visible_screen_text.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMG="/tmp/lucy_linkedin_screen.png"

"$SCRIPT_DIR/capture_screen_for_ocr.sh" "$IMG" >/dev/null
swift "$SCRIPT_DIR/ocr_screen_text.swift" "$IMG"
