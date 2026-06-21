#!/usr/bin/env /usr/local/bin/python3
"""
Lucy-created tool: reminders_dry_run.py

Purpose:
Parse a simple reminder request and print a safe preview.

This tool is dry-run only. It does not create real Reminders.app items.
"""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timedelta


def parse_request(text: str) -> dict:
    original = text.strip()
    lowered = original.lower()

    # Remove common leading phrase.
    task = re.sub(r"^\s*remind me\s+", "", original, flags=re.IGNORECASE).strip()

    date_hint = None
    time_hint = None

    if "tomorrow" in lowered:
        date_hint = "tomorrow"
    elif "today" in lowered:
        date_hint = "today"

    time_match = re.search(r"\b(?:at\s*)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b", lowered)
    if time_match:
        hour = int(time_match.group(1))
        minute = int(time_match.group(2) or "0")
        meridiem = time_match.group(3)

        if meridiem == "pm" and hour != 12:
            hour += 12
        if meridiem == "am" and hour == 12:
            hour = 0

        time_hint = f"{hour:02d}:{minute:02d}"

    # Try to remove date/time phrases from task.
    task = re.sub(r"\b(today|tomorrow)\b", "", task, flags=re.IGNORECASE)
    task = re.sub(r"\bat\s+\d{1,2}(?::\d{2})?\s*(am|pm)?\b", "", task, flags=re.IGNORECASE)
    task = re.sub(r"\s+", " ", task).strip()
    task = re.sub(r"^(to|about)\s+", "", task, flags=re.IGNORECASE).strip()

    due_preview = None
    if date_hint or time_hint:
        now = datetime.now()
        due = now
        if date_hint == "tomorrow":
            due = due + timedelta(days=1)
        if time_hint:
            hour, minute = map(int, time_hint.split(":"))
            due = due.replace(hour=hour, minute=minute, second=0, microsecond=0)
        due_preview = due.isoformat(timespec="minutes")

    return {
        "dry_run": True,
        "tool": "reminders_dry_run",
        "original_request": original,
        "parsed": {
            "title": task or original,
            "date_hint": date_hint,
            "time_hint": time_hint,
            "due_preview": due_preview,
        },
        "would_create_reminder": False,
        "safety_note": "Dry run only. No Reminders.app item was created.",
    }


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: reminders_dry_run.py 'remind me tomorrow at 3pm to call mom'", file=sys.stderr)
        return 2

    result = parse_request(" ".join(sys.argv[1:]))
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
