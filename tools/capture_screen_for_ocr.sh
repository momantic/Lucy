#!/bin/zsh
# Captures the main screen to a PNG for OCR.
# Requires Screen Recording permission for Terminal during testing or Lucy app in production.

set -e

OUT="${1:-/tmp/lucy_linkedin_screen.png}"
screencapture -x "$OUT"
echo "$OUT"
