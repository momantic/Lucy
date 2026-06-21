#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import subprocess
import sys
import urllib.parse


def run_osascript(script: str) -> tuple[int, str, str]:
    p = subprocess.run(
        ["/usr/bin/osascript", "-e", script],
        text=True,
        capture_output=True,
        timeout=30,
    )
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def extract_topic(request: str) -> str:
    lowered = request.lower()
    m = re.search(r"(?:about|on|for)\s+(.+?)(?:\s+and\s+draft|\s+then\s+draft|\s+and\s+create|\s+then\s+create|$)", request, re.I)
    if m:
        return m.group(1).strip(" .")
    return "sea turtles"


def main() -> int:
    request = " ".join(sys.argv[1:]).strip() if len(sys.argv) > 1 else "sea turtles"
    topic = extract_topic(request)
    query = f'{topic} LinkedIn posts'
    url = "https://www.linkedin.com/search/results/content/?" + urllib.parse.urlencode({"keywords": topic})

    script = f'''
    tell application "Safari"
        activate
        if (count of windows) = 0 then
            make new document with properties {{URL:"{url}"}}
        else
            set URL of current tab of front window to "{url}"
        end if
    end tell
    '''
    code, out, err = run_osascript(script)

    print(json.dumps({
        "ok": code == 0,
        "tool": "linkedin_visible_research_dry_run",
        "topic": topic,
        "opened_url": url,
        "would_do": [
            "Open LinkedIn content search in Safari",
            "Ask user to log in / scroll if needed",
            "Then use linkedin_visible_research_read.py to read visible page text",
            "Then draft a LinkedIn post from visible trends"
        ],
        "next_step": "After Safari loads LinkedIn search results, run: /tool linkedin_visible_research_read " + topic,
        "safety_note": "V1 only reads visible page text from your browser. It does not bypass login and does not post anything.",
        "stdout": out,
        "stderr": err
    }, indent=2, ensure_ascii=False))
    return 0 if code == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
