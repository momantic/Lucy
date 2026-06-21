#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import subprocess
import sys


def run_osascript(script: str) -> tuple[int, str, str]:
    p = subprocess.run(
        ["/usr/bin/osascript", "-e", script],
        text=True,
        capture_output=True,
        timeout=30,
    )
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def clean_text(text: str) -> str:
    text = re.sub(r"\s+", " ", text or "").strip()
    return text[:8000]


def simple_trends(text: str, topic: str) -> list[str]:
    lowered = text.lower()
    trends = []

    checks = [
        ("conservation", "Conservation and protection are showing up as a major theme."),
        ("plastic", "Plastic pollution appears to be a common concern."),
        ("climate", "Climate change and warming oceans appear connected to the topic."),
        ("hatchling", "Hatchlings/nesting stories may be emotionally engaging."),
        ("rescue", "Rescue and rehabilitation content may be resonating."),
        ("ocean", "Ocean ecosystem framing appears useful."),
        ("wildlife", "Wildlife protection framing appears useful."),
        ("volunteer", "Volunteer/action-oriented posts may perform well."),
    ]

    for key, sentence in checks:
        if key in lowered:
            trends.append(sentence)

    if not trends:
        trends.append(f"Visible LinkedIn text was limited, but the topic '{topic}' can be framed around conservation, ocean health, and practical action.")

    return trends[:5]


def draft_post(topic: str, trends: list[str]) -> str:
    trend_line = " ".join(trends[:2])
    return f"""Sea turtles are more than a symbol of ocean life — they are a signal for how healthy our oceans really are.

From conservation efforts to plastic pollution and habitat protection, the conversation around {topic} keeps pointing to one thing: small human choices compound into large environmental outcomes.

What stands out to me is that the most effective posts are not just about awareness. They connect the issue to action:
• reducing single-use plastics
• supporting rescue and rehabilitation groups
• protecting nesting habitats
• keeping coastlines cleaner
• sharing science in a way people can actually care about

{trend_line}

The future of sea turtles is not only a wildlife story. It is a reminder that ocean health, climate resilience, and everyday behavior are deeply connected.

What is one small action you think more people should take to protect marine life?

#SeaTurtles #OceanConservation #MarineLife #Sustainability #ClimateAction"""


def main() -> int:
    topic = " ".join(sys.argv[1:]).strip() if len(sys.argv) > 1 else "sea turtles"

    script = '''
    tell application "Safari"
        activate
        if (count of windows) = 0 then error "No Safari window is open."
        do JavaScript "document.body.innerText" in current tab of front window
    end tell
    '''
    code, out, err = run_osascript(script)

    if code != 0:
        print(json.dumps({
            "ok": False,
            "tool": "linkedin_visible_research_read",
            "topic": topic,
            "error": err or out or "Could not read Safari page text.",
            "hint": "Open LinkedIn search results in Safari first, log in if needed, then retry."
        }, indent=2, ensure_ascii=False))
        return 1

    text = clean_text(out)
    trends = simple_trends(text, topic)
    post = draft_post(topic, trends)

    print(json.dumps({
        "ok": True,
        "tool": "linkedin_visible_research_read",
        "topic": topic,
        "visible_text_chars": len(text),
        "trends": trends,
        "draft_linkedin_post": post,
        "safety_note": "Draft only. Lucy did not post to LinkedIn."
    }, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
