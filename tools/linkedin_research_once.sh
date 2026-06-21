#!/bin/zsh
set -e

TOPIC="$*"
if [ -z "$TOPIC" ]; then
  echo "Usage: tools/linkedin_research_once.sh \"topic here\""
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

osascript "$SCRIPT_DIR/linkedin_search_chrome_accessibility.applescript" "$TOPIC"

echo "Opened LinkedIn search for: $TOPIC"
echo "Waiting 5 seconds for page load..."
sleep 5

echo "Reading visible LinkedIn screen..."
"$SCRIPT_DIR/read_linkedin_chrome_screen_text.sh" 2>/dev/null
