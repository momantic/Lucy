#!/usr/bin/env /usr/local/bin/python3
"""
Lucy-created tool: calendar_create_approved.py

Purpose:
Create a Calendar.app event after explicit user approval.

Safety:
This tool is NOT dry-run. It should only be called after Lucy has shown a preview
and the user has explicitly approved creation.
"""

from __future__ import annotations

import json
import subprocess
import sys
import time

from calendar_dry_run import parse_request


def apple_script_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def create_event(parsed: dict) -> dict:
    info = parsed["parsed"]
    title = info["title"].strip()
    start_preview = info["start_preview"]
    end_preview = info["end_preview"]

    if not title:
        raise ValueError("Calendar event title is empty.")

    escaped_title = apple_script_escape(title)

    start_date, start_time = start_preview.split("T", 1)
    end_date, end_time = end_preview.split("T", 1)

    sy, sm, sd = start_date.split("-")
    ey, em, ed = end_date.split("-")
    sh, smin = start_time.split(":", 1)
    eh, emin = end_time.split(":", 1)

    # Make sure Calendar is running before AppleScript talks to it.
    subprocess.run(["/usr/bin/open", "-a", "Calendar"], text=True, capture_output=True, timeout=10)
    time.sleep(1.5)

    script = f'''
    tell application "Calendar"
        activate
        delay 1
        set targetCalendar to first calendar
        tell targetCalendar
            make new event with properties {{summary:"{escaped_title}", start date:date "{sm}/{sd}/{sy} {sh}:{smin}:00", end date:date "{em}/{ed}/{ey} {eh}:{emin}:00"}}
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
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "osascript failed")

    return {
        "created": True,
        "tool": "calendar_create_approved",
        "title": title,
        "start_preview": start_preview,
        "end_preview": end_preview,
        "safety_note": "Created only after explicit approval.",
        "osascript_stdout": proc.stdout.strip()
    }


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: calendar_create_approved.py 'schedule meeting tomorrow at 3pm called dentist'", file=sys.stderr)
        return 2

    request = " ".join(sys.argv[1:])
    parsed = parse_request(request)

    try:
        result = create_event(parsed)
    except Exception as e:
        print(json.dumps({
            "created": False,
            "tool": "calendar_create_approved",
            "error": str(e),
            "safety_note": "No event was created if AppleScript failed before completion."
        }, indent=2, ensure_ascii=False))
        return 1

    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
