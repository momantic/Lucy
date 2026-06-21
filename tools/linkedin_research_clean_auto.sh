#!/bin/zsh
set -e

TOPIC="$*"
if [ -z "$TOPIC" ]; then
  echo "Usage: tools/linkedin_research_clean_auto.sh \"topic here\""
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RAW="/tmp/lucy_linkedin_research.txt"
CLEAN="/tmp/lucy_linkedin_research_clean.txt"

"$SCRIPT_DIR/linkedin_research_to_file_auto.sh" "$TOPIC" >/dev/null 2>/dev/null

cat "$RAW" \
  | grep -v "Products |" \
  | grep -v "MCESD1" \
  | grep -v "Reply 1988" \
  | grep -v "Ask Gemini" \
  | grep -v "All Bookmarks" \
  | grep -v "Try Premium" \
  | grep -v "Premium" \
  | grep -v "Promoted" \
  | grep -v "KENWOOD" \
  | grep -v "Ad ..." \
  | grep -v "WSJ" \
  | grep -v "Wall Street Journal" \
  | grep -v "The Full Story" \
  | grep -v "More stories" \
  | grep -v "Join WSJ" \
  | grep -v "American Express" \
  | grep -v "Amex" \
  | grep -v "Gold Card" \
  | grep -v "Terms apply" \
  | grep -v "Earn over" \
  | grep -v "dining and travel" \
  | grep -v "unlock your full potential" \
  | grep -v "viewed your profile" \
  | grep -v "Try now" \
  | grep -v "About Accessibility" \
  | grep -v "Privacy & Terms" \
  | grep -v "Business Services" \
  | grep -v "Get the LinkedIn app" \
  | grep -v "Linked in LinkedIn Corporation" \
  | grep -v "Messaging" \
  | grep -v "Write better" \
  | grep -v "Write faster" \
  | grep -v "Right now" \
  | grep -v "Win at work" \
  | grep -v "Grammarly" \
  | grep -v "Get the Linkedin app" \
  | grep -v "Get the LinkedIn app" \
  | grep -v "^ChatGPT$" \
  | grep -v "Dunkin" \
  | grep -v "Credits" \
  | grep -v "Unlock Dunkin" \
  | grep -v "other connections" \
  | grep -v "also follow" \
  | grep -v "connections also" \
  | grep -v "Kenwood" \
  | grep -v "Kenwood Communications" \
  | grep -v "grow your business" \
  | grep -v "company updates" \
  | grep -v "Receive daily" \
  | grep -v "^Follow$" \
  | grep -v "^Terminal$" \
  | grep -v "^G$" \
  | grep -v "^12$" \
  | grep -v "^19$" \
  | grep -v "^AM$" \
  > "$CLEAN"

echo "$CLEAN"
