#!/bin/zsh
set -e

TOPIC="$*"
if [ -z "$TOPIC" ]; then
  echo "Usage: tools/linkedin_generate_draft_from_research.sh \"topic here\""
  exit 1
fi

RESEARCH="/tmp/lucy_linkedin_research_clean.txt"
POST_OUT="/tmp/lucy_linkedin_post.txt"
REPORT_OUT="/tmp/lucy_linkedin_draft_report.md"

if [ ! -f "$RESEARCH" ]; then
  echo "Missing research file: $RESEARCH"
  echo "Run: tools/linkedin_research_clean_auto.sh \"$TOPIC\""
  exit 1
fi

/usr/local/bin/python3 - "$TOPIC" "$RESEARCH" "$POST_OUT" "$REPORT_OUT" <<'PY'
import sys
from pathlib import Path
import re

topic = sys.argv[1]
research_path = Path(sys.argv[2])
post_out = Path(sys.argv[3])
report_out = Path(sys.argv[4])

def humanize_topic_for_sentence(topic):
    t = topic.strip()
    lower = t.lower()

    if "510" in lower:
        return "510(k)"

    # "AI agents for medical device regulatory workflows"
    # -> "medical device regulatory workflows"
    if lower.startswith("ai agents for "):
        return t[len("AI agents for "):].strip()

    if lower.startswith("ai agents in "):
        return t[len("AI agents in "):].strip()

    if lower.startswith("ai agents "):
        return t[len("AI agents "):].strip()

    if lower.endswith(" agents"):
        return t[:-7].strip()

    return t

sentence_topic = humanize_topic_for_sentence(topic)

def opening_line(topic, sentence_topic):
    lower = topic.lower()
    if "510" in lower:
        return "AI agents will not magically “do a 510(k).”"
    if lower.startswith("ai agents"):
        return f"AI agents will not magically handle {sentence_topic} on their own."
    return f"AI agents will not magically solve {sentence_topic} on their own."

raw = research_path.read_text(errors="ignore")

def clean_line(s):
    s = s.strip()
    s = re.sub(r"\s+", " ", s)
    return s

lines = [clean_line(x) for x in raw.splitlines()]
lines = [x for x in lines if x]

noise_terms = [
    "Search | LinkedIn",
    "linkedin.com",
    "Posts",
    "Sort by",
    "Date posted",
    "Content type",
    "From member",
    "All filters",
    "+ Follow",
    "... more",
    "3rd+",
]

content_lines = []
for line in lines:
    if any(term.lower() in line.lower() for term in noise_terms):
        continue
    if len(line) <= 2:
        continue
    content_lines.append(line)

joined = "\n".join(content_lines)

# Lightweight pattern detection.
has_ai_agent = bool(re.search(r"\bAI agents?\b|\bAl agents?\b", joined, re.I))
has_trust = bool(re.search(r"trust|reliable|scale|autonomy|risk|governance", joined, re.I))
has_execution = bool(re.search(r"execution|end-to-end|workflow|automation|autonomy", joined, re.I))
has_data_platform = bool(re.search(r"data platform|Snowflake|Databricks|Delta Lake|data", joined, re.I))
has_regulatory = bool(re.search(r"FDA|510|regulatory|submission|predicate|compliance", topic + " " + joined, re.I))

patterns = []
if has_ai_agent:
    patterns.append("Trending posts frame AI agents as moving from simple prompting into more autonomous execution.")
if has_trust:
    patterns.append("The stronger angle is not just capability, but trust, reliability, and risk control.")
if has_execution:
    patterns.append("People are emphasizing end-to-end workflows rather than isolated chat interactions.")
if has_data_platform:
    patterns.append("Some posts connect AI agents to the infrastructure layer: data quality, platforms, and scale.")
if has_regulatory:
    patterns.append("For regulated fields, the missing angle is evidence: how the agent proves or traces its work.")

if not patterns:
    patterns.append("Visible posts seem to favor practical claims and clear positioning over generic hype.")

# Topic-specific draft logic.
if has_regulatory or "510" in topic or "FDA" in topic.upper():
    post = f"""{opening_line(topic, sentence_topic)}

But they may change one of the most painful parts of the process:

building a defensible evidence trail.

The value is not asking an agent to write confident regulatory prose.

The value is asking it to show its work:

- Which predicate devices were considered?
- Why were some rejected?
- Which performance characteristics match?
- Where are the gaps?
- What literature or testing supports each claim?
- Which parts still require human judgment?

That distinction matters.

A regulatory submission is not just a document.
It is an argument.

And if an AI agent cannot trace where its argument came from, it is not reducing risk. It is creating a new one.

The best AI tools in regulated industries probably will not be the ones that sound the most fluent.

They will be the ones that make uncertainty visible.

Curious how regulatory, medtech, and AI people think about this:

Would you trust an AI-assisted 510(k) workflow more if every claim came with a traceable evidence map?"""
else:
    post = f"""AI agents are moving past simple prompts.

But for {sentence_topic}, the real question is not:

“Can the agent complete the task?”

The better question is:

“Can the agent show how it completed the task?”

That difference matters.

A demo can look impressive when everything goes right.
A real workflow has messy inputs, missing context, edge cases, and decisions that need to be explained later.

The useful agent is not just the one that acts.

It is the one that can:

- explain its reasoning path
- expose uncertainty
- cite its inputs
- recover from bad assumptions
- hand control back to the human at the right time

That is where I think the next wave of AI agents gets interesting.

Not just more autonomy.

More accountable autonomy.

Curious how others are thinking about this:

What would make you trust an AI agent enough to use it in a real workflow?"""

alternate_hooks = [
    f"AI agents are growing up. But {sentence_topic} needs more than autonomy.",
    f"The hard part of {sentence_topic} is not generating output. It is proving why the output should be trusted.",
]

explanations = [
    ("Hook", "Starts with a clear, slightly contrarian claim instead of generic AI hype."),
    ("Angle", "Uses the trend around AI agents becoming more autonomous, but shifts the focus to trust and evidence."),
    ("Structure", "Moves from big claim → practical distinction → concrete checklist → discussion question."),
    ("CTA", "Ends with a domain-specific question that invites serious replies instead of engagement bait."),
]

risk_notes = [
    "OCR text may be incomplete because it only reads the visible browser window.",
    "The draft is original and pattern-based; it should not copy wording from visible LinkedIn posts.",
    "User should manually review factual claims before posting.",
]

report = "# Lucy LinkedIn Draft Report\n\n"
report += f"## Topic\n\n{topic}\n\n"
report += "## Detected Patterns\n\n"
for p in patterns:
    report += f"- {p}\n"
report += "\n## Draft Post\n\n"
report += post + "\n\n"
report += "## Alternate Hooks\n\n"
for h in alternate_hooks:
    report += f"- {h}\n"
report += "\n## Why Lucy Made These Choices\n\n"
for choice, reason in explanations:
    report += f"- **{choice}:** {reason}\n"
report += "\n## Risk Notes\n\n"
for r in risk_notes:
    report += f"- {r}\n"

post_out.write_text(post)
report_out.write_text(report)

print(f"Draft post saved to: {post_out}")
print(f"Draft report saved to: {report_out}")
PY

cat "$POST_OUT" | pbcopy

echo ""
echo "Copied final LinkedIn post to clipboard."
echo "Post file: $POST_OUT"
echo "Report file: $REPORT_OUT"
echo ""
cat "$REPORT_OUT"
