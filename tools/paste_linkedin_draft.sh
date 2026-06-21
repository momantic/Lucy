#!/bin/zsh
set -e

POST="/tmp/lucy_linkedin_post.txt"

if [ ! -f "$POST" ]; then
  echo "Missing draft post: $POST"
  echo "Run: tools/linkedin_full_draft_auto.sh \"topic here\""
  exit 1
fi

cat "$POST" | pbcopy

if [ -d "/Applications/Google Chrome.app" ]; then
  osascript -e 'tell application "Google Chrome" to activate'
else
  osascript -e 'tell application "Safari" to activate'
fi

echo "Click inside the LinkedIn post text box now..."
sleep 5

osascript <<'APPLESCRIPT'
tell application "System Events"
    keystroke "v" using command down
end tell
APPLESCRIPT

echo "Pasted LinkedIn draft from: $POST"
