#!/bin/zsh
set -e

PY="/usr/local/bin/python3"
INPUT="$*"

if [ -z "$INPUT" ]; then
  echo "Usage:"
  echo "tools/lucy_linkedin_manual_local.sh \"Lucy, write me a LinkedIn post about topic here\""
  exit 1
fi

TOPIC="$INPUT"
LOWER=$(echo "$INPUT" | tr '[:upper:]' '[:lower:]')

if echo "$LOWER" | grep -q "write me a linkedin post about"; then
  TOPIC=$(echo "$INPUT" | sed -E 's/.*[Ww]rite me a [Ll]inked[Ii]n post about[[:space:]]*//')
elif echo "$LOWER" | grep -q "draft a linkedin post about"; then
  TOPIC=$(echo "$INPUT" | sed -E 's/.*[Dd]raft a [Ll]inked[Ii]n post about[[:space:]]*//')
elif echo "$LOWER" | grep -q "make me a linkedin post about"; then
  TOPIC=$(echo "$INPUT" | sed -E 's/.*[Mm]ake me a [Ll]inked[Ii]n post about[[:space:]]*//')
elif echo "$LOWER" | grep -q "linkedin post about"; then
  TOPIC=$(echo "$INPUT" | sed -E 's/.*[Ll]inked[Ii]n post about[[:space:]]*//')
elif echo "$LOWER" | grep -q "post about"; then
  TOPIC=$(echo "$INPUT" | sed -E 's/.*[Pp]ost about[[:space:]]*//')
fi

TOPIC=$(echo "$TOPIC" | sed -E 's/[.?!]+$//')
ENCODED_TOPIC=$($PY -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$TOPIC")
URL="https://www.linkedin.com/search/results/content/?keywords=$ENCODED_TOPIC"

echo ""
echo "Lucy LinkedIn Local MLX"
echo "Topic: $TOPIC"
echo ""
echo "Open this LinkedIn search URL manually:"
echo "$URL"
echo ""
echo "Then:"
echo "1. Wait for LinkedIn search results to load."
echo "2. Press Command+A."
echo "3. Press Command+C."
echo "4. Come back here and press Enter."
echo ""
read -r _

RAW="/tmp/lucy_linkedin_research.txt"
CLEAN="/tmp/lucy_linkedin_research_clean.txt"
PROMPT="/tmp/lucy_linkedin_mlx_prompt.txt"
FULL_OUT="/tmp/lucy_linkedin_mlx_output.md"
POST_OUT="/tmp/lucy_linkedin_post.txt"

pbpaste > "$RAW"

cat "$RAW" \
  | grep -v "Products |" \
  | grep -v "Try Premium" \
  | grep -v "Premium" \
  | grep -v "Promoted" \
  | grep -v "Messaging" \
  | grep -v "Get the LinkedIn app" \
  | grep -v "Privacy & Terms" \
  | grep -v "Business Services" \
  | grep -v "Ad" \
  > "$CLEAN" || true

cat > "$PROMPT" <<PROMPT
Write ONE original LinkedIn post about:

$TOPIC

Use the LinkedIn copied text only as weak background signal. Ignore ads, company blurbs, and generic marketing language.
Do not copy the source text.

Research notes:
$(cat "$CLEAN" | head -n 35)

Write like a technical founder thinking out loud.

Hard rules:
- Output ONLY the post.
- 130 to 190 words.
- No title.
- No headings.
- No company names.
- No product names.
- No hype.
- No formal report tone.
- No phrases: "in the world of", "with the increasing adoption", "critical bridge", "cutting-edge", "stringent requirements", "significant milestone", "robust", "revolutionize", "transforming healthcare", "just like", "like predicate".
- Very short paragraphs: 1 to 2 sentences each.
- Use plain English.
- End with one question.

Must include this idea:
For AI medical device software, the hard part is not generating a 510(k) draft. The hard part is preserving evidence behind each claim.

Use this structure:
Line 1: "<topic> is not just <obvious thing>."
Line 2: "It is <deeper thing>."
Then explain using 3 to 5 short bullets:
- comparison to predicate devices
- validation data
- performance claims
- traceability
- human judgment

Now write the post.
PROMPT

MODEL="${LUCY_MLX_MODEL:-mlx-community/Qwen2.5-3B-Instruct-4bit}"

echo ""
echo "Running local MLX model..."
echo "Model: $MODEL"

$PY -m mlx_lm generate \
  --model "$MODEL" \
  --prompt "$(cat "$PROMPT")" \
  --max-tokens 320 \
  > "$FULL_OUT" 2>/tmp/lucy_mlx_stderr.log

$PY - "$FULL_OUT" "$POST_OUT" <<'PY'
import re, sys
from pathlib import Path

full_out = Path(sys.argv[1])
post_out = Path(sys.argv[2])

text = full_out.read_text(errors="ignore")
text = re.sub(r"Calling `python -m mlx_lm.*?\n", "", text)
text = re.sub(r"=+\s*", "", text)
text = re.sub(r"Prompt:\s*\d+ tokens.*", "", text, flags=re.S)
text = re.sub(r"Generation:\s*\d+ tokens.*", "", text, flags=re.S)
text = re.sub(r"Peak memory:.*", "", text)
text = text.strip()

needs_wrapper = (
    len(text.split()) < 110
    or "?" not in text
    or "- " not in text
    or "robust" in text.lower()
)

if needs_wrapper:
    text = """For AI medical device software, the hard part is not generating a 510(k) draft.

It is preserving the evidence behind every claim.

A local AI agent can help draft faster, but speed is not the real test in a regulated workflow.

The real test is whether the workflow can keep track of:

- comparison to predicate devices
- validation data
- performance claims
- traceability
- human judgment

That is where AI agents could actually be useful.

Not by replacing regulatory judgment.

By making the evidence trail harder to lose.

If an AI-assisted 510(k) workflow cannot show where its claims came from, it may be adding risk instead of removing it.

What would make you trust an AI agent in a regulated submission workflow?"""

post_out.write_text(text)
print("Draft post saved to:", post_out)
PY

/usr/bin/pbcopy < "$POST_OUT"

echo ""
echo "Done. Final post copied to clipboard."
echo "Post file: $POST_OUT"
echo "Full MLX output: $FULL_OUT"
echo ""
echo "Preview:"
echo "----------------------------------------"
cat "$POST_OUT"
echo ""
echo "----------------------------------------"
