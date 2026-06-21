#!/bin/zsh
set -e

TOPIC="$*"
if [ -z "$TOPIC" ]; then
  echo "Usage: tools/linkedin_full_draft_auto.sh \"topic here\""
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Step 1: Researching visible LinkedIn posts..."
"$SCRIPT_DIR/linkedin_research_clean_auto.sh" "$TOPIC"

echo ""
echo "Step 2: Generating draft..."
"$SCRIPT_DIR/linkedin_generate_draft_from_research.sh" "$TOPIC"

echo ""
echo "Done. Final post copied to clipboard."
echo "Open LinkedIn composer when ready."
