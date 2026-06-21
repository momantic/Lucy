#!/bin/zsh
set -euo pipefail
export PYTHONUNBUFFERED=1

REQ="${*:-}"
PY="/usr/local/bin/python3"
MODEL="${LUCY_LINKEDIN_MODEL:-mlx-community/Qwen2.5-3B-Instruct-4bit}"

RESEARCH_OUT="/tmp/lucy_linkedin_research.txt"
POST_OUT="/tmp/lucy_linkedin_post.txt"
MLX_OUT="/tmp/lucy_linkedin_mlx_output.md"
PROMPT_OUT="/tmp/lucy_linkedin_mlx_prompt.txt"

rm -f "$POST_OUT" "$MLX_OUT" "$PROMPT_OUT"

TOPIC="$(python3 -c 'import sys,re
low=" ".join(sys.argv[1:]).strip().lower()
fixes={"wirte":"write","wrtie":"write","wriet":"write","linekdin":"linkedin","linkdin":"linkedin","linkedn":"linkedin","psot":"post","pst":"post"}
for a,b in fixes.items():
    low=low.replace(a,b)
m=re.search(r"(?:write|draft|make|create).*?linkedin\s+post\s+(?:about|on)\s+(.+)", low)
print(m.group(1).strip() if m else low)
' "$REQ")"
[ -z "$TOPIC" ] && TOPIC="$REQ"

echo "Lucy LinkedIn Direct MLX"
echo "Topic: $TOPIC"
echo "Lucy: 🔎 Researching LinkedIn..."
echo "Opening LinkedIn with Lucy Browser Bridge..."

BROWSER_JSON="/tmp/lucy_browser_state.json"
python3 tools_created_by_lucy/lucy_browser.py linkedin_search "$TOPIC" > "$BROWSER_JSON" 2>/tmp/lucy_browser_err.log || true
sleep 4
python3 tools_created_by_lucy/lucy_browser.py read > "$BROWSER_JSON" 2>/tmp/lucy_browser_err.log || true

RESEARCH_TEXT="$(python3 tools_created_by_lucy/lucy_browser.py page_text 2>/dev/null || true)"
WORD_COUNT="$(printf "%s" "$RESEARCH_TEXT" | wc -w | tr -d ' ')"

if [ "$WORD_COUNT" -lt 20 ]; then
  echo "Warning: Browser Bridge research was weak or failed. Drafting from topic only."
  RESEARCH_TEXT="No useful LinkedIn Browser Bridge research was captured. Draft from the topic only."
else
  echo "Lucy: 📄 Read $WORD_COUNT words from LinkedIn."
echo "Captured LinkedIn Browser Bridge research: $WORD_COUNT words"
fi

ANALYSIS_OUT="/tmp/lucy_linkedin_analysis.md"
REVIEW_OUT="/tmp/lucy_linkedin_review.md"
FINAL_PROMPT_OUT="/tmp/lucy_linkedin_final_prompt.txt"

cat > "$PROMPT_OUT" <<PROMPT
You are Lucy's LinkedIn research analyst.

Topic:
$TOPIC

LinkedIn research text:
$RESEARCH_TEXT

Extract the useful signal from this research. Ignore navigation, ads, profile noise, reaction counts, and repeated UI text.

Return a concise research brief with these sections:
1. Main trend across the results
2. 5-8 concrete signals/examples from different posts
3. Companies/products/people mentioned
4. Risks or tensions
5. Best angle for a thoughtful LinkedIn post

Do not write the final LinkedIn post yet.
PROMPT

echo ""
echo "Lucy Progress"
echo "[✓] Research"
echo "[⟳] Analysis"
echo "[ ] Writing"
echo "[ ] Review"
echo ""
echo "Lucy: Extracting themes and signals..."
echo "Analyzing LinkedIn research..."

"$PY" -m mlx_lm generate \
  --model "$MODEL" \
  --prompt "$(cat "$PROMPT_OUT")" \
  --max-tokens 700 > "$ANALYSIS_OUT" 2>&1 || true

"$PY" <<'PY2'
from pathlib import Path
import re

raw = Path("/tmp/lucy_linkedin_analysis.md").read_text(errors="ignore")
txt = raw
if "==========" in txt:
    parts = txt.split("==========")
    if len(parts) >= 3:
        txt = parts[1]
txt = txt.replace("<|im_end|>", "").strip()
Path("/tmp/lucy_linkedin_analysis_clean.md").write_text(txt, encoding="utf-8")
PY2

ANALYSIS_TEXT="$(cat /tmp/lucy_linkedin_analysis_clean.md 2>/dev/null || true)"

cat > "$FINAL_PROMPT_OUT" <<PROMPT
You are Lucy's LinkedIn writer.

Topic:
$TOPIC

Research brief:
$ANALYSIS_TEXT

Original LinkedIn page context:
$RESEARCH_TEXT

Write ONE polished LinkedIn post that synthesizes the whole research set.

Requirements:
- 220-320 words.
- Strong hook in the first line.
- Do not summarize only one post.
- Use at least 3 distinct signals/examples from the research.
- Separate analysis tools from execution/trading agents if relevant.
- Include one tension/risk/open question.
- Sound like a thoughtful founder/operator/engineer, not a generic marketer.
- No fake identity. Do not say "our team", "my research", "we launched", or imply the user owns any product.
- Do not mention that you analyzed LinkedIn.
- Short paragraphs.
- End with a sharp question.
- Output only the final post.
PROMPT

echo ""
echo "Lucy Progress"
echo "[✓] Research"
echo "[✓] Analysis"
echo "[⟳] Writing"
echo "[ ] Review"
echo ""
echo "Lucy: Writing synthesized draft..."
echo "Writing synthesized LinkedIn draft..."

"$PY" -m mlx_lm generate \
  --model "$MODEL" \
  --prompt "$(cat "$FINAL_PROMPT_OUT")" \
  --max-tokens 850 > "$MLX_OUT" 2>&1
STATUS=$?

set +e
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
bad = [
    "Lucy LinkedIn Direct MLX",
    "Opening LinkedIn search. Using existing OCR cache if available...",
    "As a member of STEM",
    "as a member of STEM",
    "freshwater connoisseur",
    "freshwater enthusiast,",
]
for b in bad:
    text = text.replace(b, "")

text = text.replace("-- END DRAFT --", "").replace("--- END DRAFT ---", "")
text = "\n".join(line.strip() for line in text.splitlines() if line.strip())
print(text)
print("--- END DRAFT ---")
PY
