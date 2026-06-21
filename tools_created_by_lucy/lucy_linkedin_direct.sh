#!/bin/zsh
set -euo pipefail

REQ="${*:-}"
PY="/usr/local/bin/python3"
MODEL="${LUCY_LINKEDIN_MODEL:-mlx-community/Qwen2.5-3B-Instruct-4bit}"

RESEARCH_OUT="/tmp/lucy_linkedin_research.txt"
POST_OUT="/tmp/lucy_linkedin_post.txt"
MLX_OUT="/tmp/lucy_linkedin_mlx_output.md"
PROMPT_OUT="/tmp/lucy_linkedin_mlx_prompt.txt"

rm -f "$RESEARCH_OUT" "$POST_OUT" "$MLX_OUT" "$PROMPT_OUT"

TOPIC="$(printf "%s" "$REQ" | sed -E 's/^[Ll]ucy,? *//; s/[Ww]rite me a [Ll]inked[Ii]n post (about|on) //; s/[Dd]raft a [Ll]inked[Ii]n post (about|on) //; s/[Mm]ake me a [Ll]inked[Ii]n post (about|on) //')"
[ -z "$TOPIC" ] && TOPIC="$REQ"

echo "Lucy LinkedIn Direct MLX"
echo "Topic: $TOPIC"
echo "Opening LinkedIn and reading visible Chrome page with screenshot/OCR..."

set +e
tools/linkedin_research_to_file.sh "$TOPIC"
OCR_STATUS=$?
set -e

RESEARCH_TEXT="$(cat "$RESEARCH_OUT" 2>/dev/null || true)"
WORD_COUNT="$(printf "%s" "$RESEARCH_TEXT" | wc -w | tr -d ' ')"

if [ "$OCR_STATUS" -ne 0 ] || [ "$WORD_COUNT" -lt 20 ]; then
  echo "Warning: OCR research was weak or failed. Drafting from topic only."
  RESEARCH_TEXT="No useful LinkedIn OCR research was captured. Draft from the topic only."
else
  echo "Captured LinkedIn OCR research: $WORD_COUNT words"
fi

cat > "$PROMPT_OUT" <<PROMPT
You are Lucy, drafting a LinkedIn post.

Topic:
$TOPIC

Visible LinkedIn search/OCR context:
$RESEARCH_TEXT

Task:
Write a polished LinkedIn post inspired by the visible LinkedIn context and the topic.

Rules:
- 120-180 words.
- Sound like a real LinkedIn post, not a generic essay.
- Use short paragraphs.
- Include a strong opening hook.
- Include 1-2 concrete insights from the context if relevant.
- Do not invent names, dates, papers, companies, or first-person claims unless they appear in the context.
- Never say 'our team', 'we discovered', or imply the user did the research unless the user explicitly says so.
- If context is noisy, use it only for style and framing.
- End with a thoughtful question.
- Output only the final post.
PROMPT

echo "Running local MLX model..."

set +e
"$PY" -m mlx_lm generate \
  --model "$MODEL" \
  --prompt "$(cat "$PROMPT_OUT")" \
  --max-tokens 420 > "$MLX_OUT" 2>&1
STATUS=$?
set -e

"$PY" <<'PY'
from pathlib import Path
import re

raw = Path("/tmp/lucy_linkedin_mlx_output.md").read_text(errors="ignore")
text = raw

if "==========" in text:
    parts = text.split("==========")
    if len(parts) >= 3:
        text = parts[1]

for marker in ["Generation:", "Output:", "Response:"]:
    if marker in text:
        text = text.split(marker)[-1]

text = text.replace("<|im_end|>", "").strip()
text = re.sub(r"^.*?Output only the final post\.", "", text, flags=re.S).strip()

Path("/tmp/lucy_linkedin_post.txt").write_text(text + "\n", encoding="utf-8")

print()
print("Lucy:")
print("Draft complete.")
print()
print("--- LINKEDIN DRAFT ---")
print(text)
print("--- END DRAFT ---")
PY
