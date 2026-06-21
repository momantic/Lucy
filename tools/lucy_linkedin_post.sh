#!/bin/zsh
set -e

TOPIC="$*"

if [ -z "$TOPIC" ]; then
  echo "Usage: tools/lucy_linkedin_post.sh \"topic here\""
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Lucy LinkedIn Assistant"
echo "Topic: $TOPIC"
echo ""

echo "1. Researching visible LinkedIn posts..."
"$SCRIPT_DIR/linkedin_research_clean_auto.sh" "$TOPIC" >/dev/null

echo "2. Generating original LinkedIn draft..."
"$SCRIPT_DIR/linkedin_generate_draft_from_research.sh" "$TOPIC" >/dev/null

echo "3. Copying draft to clipboard..."
cat /tmp/lucy_linkedin_post.txt | pbcopy

echo ""
echo "Done."
echo ""
echo "Final post copied to clipboard."
echo "Draft file: /tmp/lucy_linkedin_post.txt"
echo "Explanation report: /tmp/lucy_linkedin_draft_report.md"
echo ""
echo "Now:"
echo "1. Open LinkedIn composer"
echo "2. Press Command+V"
echo "3. Review manually"
echo "4. Click Post yourself"
echo ""
echo "Preview:"
echo "----------------------------------------"
cat /tmp/lucy_linkedin_post.txt
echo ""
echo "----------------------------------------"
