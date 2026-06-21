#!/bin/zsh
set -e

TOPIC="$*"

if [ -z "$TOPIC" ]; then
  echo "Usage: tools/linkedin_build_llm_prompt.sh \"topic here\""
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESEARCH="/tmp/lucy_linkedin_research_clean.txt"
PROMPT_OUT="/tmp/lucy_linkedin_llm_prompt.md"

echo "Researching LinkedIn visible content..."
"$SCRIPT_DIR/linkedin_research_clean_auto.sh" "$TOPIC" >/dev/null

if [ ! -f "$RESEARCH" ]; then
  echo "Missing research file: $RESEARCH"
  exit 1
fi

cat > "$PROMPT_OUT" <<PROMPT
You are Lucy, a desktop AI companion helping the user draft an original LinkedIn post.

The user asked:

"$TOPIC"

You have visible-screen OCR text from LinkedIn search results. The OCR may contain noise, ads, sidebar text, repeated navigation labels, or partial posts. Treat it as weak trend signal, not as complete truth.

Your job:

1. Analyze the visible LinkedIn content.
2. Identify what kinds of posts/angles seem to be showing up.
3. Do not copy wording from any visible post.
4. Draft an original LinkedIn post in the user's voice.
5. Explain why you made each writing choice.
6. Include alternate hooks.
7. Include risk notes if any claims need verification.

User voice:

- direct
- curious
- technical but readable
- skeptical of hype
- builder/operator perspective
- no fake personal anecdotes
- no excessive emojis
- no generic "AI is changing everything"
- no engagement bait
- no copying from source posts

Desired output format:

# Draft Post

<the final LinkedIn post>

# Alternate Hooks

- <hook 1>
- <hook 2>
- <hook 3>

# Why This Works

- Hook:
- Structure:
- Angle:
- CTA:
- What was avoided:

# Risk Notes

- <anything the user should verify before posting>

Visible LinkedIn OCR research:

---
$(cat "$RESEARCH")
---
PROMPT

cat "$PROMPT_OUT" | pbcopy

echo "Built LLM prompt:"
echo "$PROMPT_OUT"
echo ""
echo "Copied prompt to clipboard."
echo ""
echo "Preview:"
echo "----------------------------------------"
cat "$PROMPT_OUT" | head -n 120
echo "----------------------------------------"
