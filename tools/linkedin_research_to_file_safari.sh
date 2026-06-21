#!/bin/zsh
set -e

TOPIC="$*"
if [ -z "$TOPIC" ]; then
  echo "Usage: tools/linkedin_research_to_file_safari.sh \"topic here\""
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="/tmp/lucy_linkedin_research.txt"

osascript "$SCRIPT_DIR/linkedin_search_safari_accessibility.applescript" "$TOPIC"

echo "Opened LinkedIn Safari search for: $TOPIC"
echo "Waiting 5 seconds for page load..."
sleep 5

echo "Reading Safari window into: $OUT"
"$SCRIPT_DIR/read_linkedin_safari_window_text.sh" > "$OUT"

echo "$OUT"
