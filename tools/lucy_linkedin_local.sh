#!/bin/zsh
set -e

INPUT="$*"

if [ -z "$INPUT" ]; then
  echo "Usage:"
  echo "tools/lucy_linkedin_local.sh \"Lucy, write me a LinkedIn post about FDA 510(k) regulatory AI medical device software\""
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TOPIC=$(/usr/local/bin/python3 - "$INPUT" <<'PY'
import sys, re

text = sys.argv[1].strip()
lower = text.lower()

patterns = [
    r"write me a linkedin post about\s+(.+)",
    r"draft a linkedin post about\s+(.+)",
    r"make me a linkedin post about\s+(.+)",
    r"create a linkedin post about\s+(.+)",
    r"linkedin post about\s+(.+)",
    r"post about\s+(.+)",
]

for pat in patterns:
    m = re.search(pat, lower, re.I)
    if m:
        start = m.start(1)
        topic = text[start:].strip()
        topic = re.sub(r"[.?!]+$", "", topic).strip()
        print(topic)
        sys.exit(0)

print("")
PY
)

if [ -z "$TOPIC" ]; then
  echo "I could not find the LinkedIn topic."
  echo ""
  echo "Try:"
  echo "tools/lucy_linkedin_local.sh \"Lucy, write me a LinkedIn post about FDA 510(k) regulatory AI medical device software\""
  exit 1
fi

echo "Lucy local LinkedIn assistant"
echo "Intent: LinkedIn post draft"
echo "Topic: $TOPIC"
echo "Model: ${LUCY_MLX_MODEL:-mlx-community/Qwen2.5-3B-Instruct-4bit}"
echo ""

"$SCRIPT_DIR/linkedin_generate_draft_with_mlx.sh" "$TOPIC"

echo ""
echo "Final draft copied to clipboard."
echo "Open LinkedIn composer and press Command+V manually."
echo ""
echo "Files:"
echo "- Post: /tmp/lucy_linkedin_post.txt"
echo "- Full MLX output: /tmp/lucy_linkedin_mlx_output.md"
echo "- Clean research: /tmp/lucy_linkedin_research_clean.txt"
