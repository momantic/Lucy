#!/bin/zsh
set -e

INPUT="$*"

if [ -z "$INPUT" ]; then
  echo "Usage: tools/lucy_command.sh \"Lucy, write me a LinkedIn post about topic here\""
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TOPIC=$(/usr/local/bin/python3 - "$INPUT" <<'PY'
import sys, re

text = sys.argv[1].strip()

patterns = [
    r"write me a linkedin post about\s+(.+)",
    r"draft a linkedin post about\s+(.+)",
    r"make me a linkedin post about\s+(.+)",
    r"linkedin post about\s+(.+)",
    r"post about\s+(.+)",
]

lower = text.lower()

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
  echo "I understood the command, but could not find a LinkedIn topic."
  echo "Try: tools/lucy_command.sh \"Lucy, write me a LinkedIn post about FDA 510(k) AI agents\""
  exit 1
fi

echo "Lucy understood:"
echo "Intent: LinkedIn post draft"
echo "Topic: $TOPIC"
echo ""

"$SCRIPT_DIR/lucy_linkedin_post.sh" "$TOPIC"
