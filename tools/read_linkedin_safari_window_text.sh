#!/bin/zsh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMG="/tmp/lucy_linkedin_safari_window.png"

osascript -e 'tell application "Safari" to activate'
sleep 1

BOUNDS=$(osascript <<'APPLESCRIPT'
tell application "Safari"
    activate
    if (count of windows) = 0 then error "No Safari window open"
    set b to bounds of front window
    set x1 to item 1 of b
    set y1 to item 2 of b
    set x2 to item 3 of b
    set y2 to item 4 of b
    set w to x2 - x1
    set h to y2 - y1
    return (x1 as string) & "," & (y1 as string) & "," & (w as string) & "," & (h as string)
end tell
APPLESCRIPT
)

BOUNDS=$(echo "$BOUNDS" | tr -d ' ')

echo "Safari bounds: $BOUNDS" >&2

screencapture -x -R "$BOUNDS" "$IMG"
swift "$SCRIPT_DIR/ocr_screen_text.swift" "$IMG" 2>/dev/null | grep -v "Unable to find a valid E5"
