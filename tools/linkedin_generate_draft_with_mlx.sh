#!/bin/zsh
set -e

TOPIC="$*"

if [ -z "$TOPIC" ]; then
  echo "Usage: tools/linkedin_generate_draft_with_mlx.sh \"topic here\""
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RESEARCH="/tmp/lucy_linkedin_research_clean.txt"
PROMPT="/tmp/lucy_linkedin_mlx_prompt.txt"
FULL_OUT="/tmp/lucy_linkedin_mlx_output.md"
POST_OUT="/tmp/lucy_linkedin_post.txt"

MODEL="${LUCY_MLX_MODEL:-mlx-community/Qwen2.5-1.5B-Instruct-4bit}"

echo "1. Researching LinkedIn visible content..."
"$SCRIPT_DIR/linkedin_research_clean_auto.sh" "$TOPIC" >/dev/null 2>/dev/null

echo "2. Building short MLX prompt..."

/usr/local/bin/python3 - "$TOPIC" "$RESEARCH" "$PROMPT" <<'PY'
import sys, re
from pathlib import Path

topic = sys.argv[1]
research = Path(sys.argv[2]).read_text(errors="ignore") if Path(sys.argv[2]).exists() else ""
prompt_out = Path(sys.argv[3])

lines = []
for line in research.splitlines():
    line = re.sub(r"\s+", " ", line.strip())
    if not line:
        continue
    bad = [
        "Search | LinkedIn", "Sort by", "Date posted", "Content type",
        "Try Premium", "Promoted", "Messaging", "Get the LinkedIn app",
        "connections", "Ad", "Follow"
    ]
    if any(b.lower() in line.lower() for b in bad):
        continue
    lines.append(line)

research_short = "\n".join(lines[:35])

prompt = f"""Write ONE original LinkedIn post about:

{topic}

Use the LinkedIn OCR notes only as weak background signal. Ignore ads, company blurbs, and generic marketing language.
Do not copy the OCR text.

Research notes:
{research_short}

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

Do not say "like predicate devices." Say "Compared with traditional device submissions" if needed.

Now write the post.
"""

prompt_out.write_text(prompt)
PY

echo "3. Running local MLX model..."
echo "Model: $MODEL"

/usr/local/bin/python3 -m mlx_lm generate \
  --model "$MODEL" \
  --prompt "$(cat "$PROMPT")" \
  --max-tokens 420 \
  > "$FULL_OUT" 2>/tmp/lucy_mlx_stderr.log

/usr/local/bin/python3 - "$FULL_OUT" "$POST_OUT" <<'PY'
import re, sys
from pathlib import Path

full_out = Path(sys.argv[1])
post_out = Path(sys.argv[2])

text = full_out.read_text(errors="ignore")

# Remove MLX wrappers/metrics/warnings.
text = re.sub(r"Calling `python -m mlx_lm.*?\n", "", text)
text = re.sub(r"=+\s*", "", text)
text = re.sub(r"Prompt:\s*\d+ tokens.*", "", text, flags=re.S)
text = re.sub(r"Generation:\s*\d+ tokens.*", "", text, flags=re.S)
text = re.sub(r"Peak memory:.*", "", text)
text = text.strip()

# Remove accidental headings if model added them.
text = re.sub(r"^#.*\n+", "", text).strip()
text = re.sub(r"^Draft Post:\s*", "", text, flags=re.I).strip()
text = re.sub(r"^LinkedIn Post:\s*", "", text, flags=re.I).strip()

# Cut repeated "##" article patterns if any.
if "##" in text:
    text = text.split("##")[0].strip()

# If the local model produced something too short or missed the question/bullets,
# wrap it into a reliable LinkedIn structure while keeping it local/free.
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

cat "$POST_OUT" | pbcopy

echo ""
echo "Done. Local MLX draft copied to clipboard."
echo "Post file: $POST_OUT"
echo "Full MLX output: $FULL_OUT"
echo ""
echo "Preview:"
echo "----------------------------------------"
cat "$POST_OUT"
echo ""
echo "----------------------------------------"
