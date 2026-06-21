#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime
# LUCY_TODAY_GUARD: always resolve relative dates from real local system date

from reminders_dry_run import parse_request


def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def main() -> int:
    if len(sys.argv) < 2:
        print('Usage: reminders_create_approved.py "remind me to workout tomorrow"', file=sys.stderr)
        return 2

    request = " ".join(sys.argv[1:])
    parsed = parse_request(request)
    info = parsed["parsed"]

    title = info["title"]
    due = datetime.fromisoformat(info["due_iso"])

    # AppleScript date constructor uses month/day/year/hour/min/sec.
    script = f'''
    tell application "Reminders"
        activate
        set dueDate to current date
        set year of dueDate to {due.year}
        set month of dueDate to {due.month}
        set day of dueDate to {due.day}
        set hours of dueDate to {due.hour}
        set minutes of dueDate to {due.minute}
        set seconds of dueDate to 0
        tell default list
            make new reminder with properties {{name:"{esc(title)}", due date:dueDate}}
        end tell
    end tell
    '''

    proc = subprocess.run(
        ["/usr/bin/osascript", "-e", script],
        text=True,
        capture_output=True,
        timeout=30,
    )

    if proc.returncode != 0:
        print(json.dumps({
            "created": False,
            "tool": "reminders_create_approved",
            "error": proc.stderr.strip() or proc.stdout.strip() or "osascript failed",
            "parsed": info
        }, indent=2, ensure_ascii=False))
        return 1

    print(json.dumps({
        "created": True,
        "tool": "reminders_create_approved",
        "title": title,
        "due_preview": info["due_preview"],
        "assumptions": info.get("assumptions", []),
        "safety_note": "Created reminder only after explicit approval."
    }, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
