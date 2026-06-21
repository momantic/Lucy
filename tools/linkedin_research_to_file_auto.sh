#!/bin/zsh
set -e

TOPIC="$*"
if [ -z "$TOPIC" ]; then
  echo "Usage: tools/linkedin_research_to_file_auto.sh \"topic here\""
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if osascript -e 'application "Google Chrome" is running' >/dev/null 2>&1 || [ -d "/Applications/Google Chrome.app" ]; then
  echo "Using Chrome..."
  "$SCRIPT_DIR/linkedin_research_to_file.sh" "$TOPIC"
else
  echo "Chrome not found. Using Safari..."
  "$SCRIPT_DIR/linkedin_research_to_file_safari.sh" "$TOPIC"
fi
