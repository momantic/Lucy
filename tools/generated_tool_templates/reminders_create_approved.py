#!/usr/bin/env /usr/local/bin/python3
"""
Lucy-created tool: reminders_create_approved.py

Purpose:
Create a Reminders.app item after explicit user approval.

Safety:
This tool is NOT dry-run. It should only be called after Lucy has shown a preview
and the user has explicitly approved creation.
"""

from __future__ import annotations

import json
import subprocess
import sys

from reminders_dry_run import parse_request


def apple_script_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def create_reminder(parsed: dict) -> dict:
    title = parsed["parsed"]["title"].strip()
    due_preview = parsed["parsed"].get("due_preview")

    if not title:
        raise ValueError("Reminder title is empty.")

    escaped_title = apple_script_escape(title)

    if due_preview:
        # due_preview is like 2026-06-15T15:00.
        date_part, time_part = due_preview.split("T", 1)
        year, month, day = date_part.split("-")
        hour, minute = time_part.split(":", 1)

        script = f'''
        tell application "Reminders"
            set newReminder to make new reminder with properties {{name:"{escaped_title}"}}
            set due date of newReminder to current date
            tell newReminder
                set due date to date "{month}/{day}/{year} {hour}:{minute}:00"
            end tell
        end tell
        '''
    else:
        script = f'''
        tell application "Reminders"
            make new reminder with properties {{name:"{escaped_title}"}}
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
        "tool": "reminders_create_approved",
        "title": title,
        "due_preview": due_preview,
        "safety_note": "Created only after explicit approval.",
        "osascript_stdout": proc.stdout.strip(),
    }


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: reminders_create_approved.py 'remind me tomorrow at 3pm to call mom'", file=sys.stderr)
        return 2

    request = " ".join(sys.argv[1:])
    parsed = parse_request(request)

    try:
        result = create_reminder(parsed)
    except Exception as e:
        print(json.dumps({
            "created": False,
            "tool": "reminders_create_approved",
            "error": str(e),
            "safety_note": "No reminder was created if AppleScript failed before completion."
        }, indent=2, ensure_ascii=False))
        return 1

    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
