#!/bin/zsh
set -e

TOPIC="$*"

if [ -z "$TOPIC" ]; then
  echo "Usage: tools/lucy_linkedin_llm_ready.sh \"topic here\""
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Lucy LinkedIn LLM Draft Prep"
echo "Topic: $TOPIC"
echo ""

echo "1. Researching LinkedIn visible content..."
"$SCRIPT_DIR/linkedin_build_llm_prompt.sh" "$TOPIC" >/dev/null

echo "2. LLM prompt copied to clipboard."
echo ""
echo "Prompt file:"
echo "/tmp/lucy_linkedin_llm_prompt.md"
echo ""
echo "Now paste the clipboard into Lucy's LLM / ChatGPT / Claude / local model."
echo ""
echo "Preview:"
echo "----------------------------------------"
cat /tmp/lucy_linkedin_llm_prompt.md | head -n 80
echo "----------------------------------------"
