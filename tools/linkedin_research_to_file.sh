#!/bin/zsh
set -euo pipefail

TOPIC="${*:-}"
OUT="/tmp/lucy_linkedin_research.txt"
URL="https://www.linkedin.com/search/results/content/?keywords=$(python3 - <<PY
import urllib.parse
print(urllib.parse.quote("$TOPIC"))
PY
)"

osascript <<OSA
tell application "Google Chrome"
    activate
    if (count of windows) = 0 then make new window
    set URL of active tab of front window to "$URL"
end tell
OSA

echo "Opened LinkedIn search for: $TOPIC"
echo "Waiting 6 seconds for page load..."
sleep 6

osascript <<'OSA' > "$OUT"
tell application "Google Chrome"
    execute active tab of front window javascript "document.body.innerText"
end tell
OSA

echo "$OUT"
