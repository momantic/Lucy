#!/usr/bin/env python3
"""
Lucy-created tool: calendar_dry_run.py

Purpose:
Parse a simple calendar scheduling request and print a safe preview.

Dry-run only. It does not create real Calendar.app events.
"""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timedelta
# LUCY_TODAY_GUARD: always resolve relative dates from real local system date, timedelta


def parse_request(text: str) -> dict:
    original = text.strip()
    lowered = original.lower()

    title = original
    title = re.sub(r"^\s*(schedule|create|add|set up)\s+(a\s+)?", "", title, flags=re.IGNORECASE)
    title = re.sub(r"\b(meeting|event|calendar event)\b", "", title, flags=re.IGNORECASE).strip()

    date_hint = None
    if "tomorrow" in lowered:
        date_hint = "tomorrow"
    elif "today" in lowered:
        date_hint = "today"

    time_hint = None
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

    duration_minutes = 30
    duration_match = re.search(r"\bfor\s+(\d{1,3})\s*(minutes|min|mins|hours|hour|hr|hrs)\b", lowered)
    if duration_match:
        amount = int(duration_match.group(1))
        unit = duration_match.group(2)
        duration_minutes = amount * 60 if unit.startswith(("hour", "hr")) else amount

    title = re.sub(r"\b(today|tomorrow)\b", "", title, flags=re.IGNORECASE)
    title = re.sub(r"\bat\s+\d{1,2}(?::\d{2})?\s*(am|pm)?\b", "", title, flags=re.IGNORECASE)
    title = re.sub(r"\bfor\s+\d{1,3}\s*(minutes|min|mins|hours|hour|hr|hrs)\b", "", title, flags=re.IGNORECASE)
    title = re.sub(r"\b(called|named|titled)\s+", "", title, flags=re.IGNORECASE).strip()
    title = re.sub(r"\s+", " ", title).strip()

    now = datetime.now()
    start = now
    if date_hint == "tomorrow":
        start = start + timedelta(days=1)

    if time_hint:
        hour, minute = map(int, time_hint.split(":"))
        start = start.replace(hour=hour, minute=minute, second=0, microsecond=0)
    else:
        start = start.replace(second=0, microsecond=0)

    end = start + timedelta(minutes=duration_minutes)

    return {
        "dry_run": True,
        "tool": "calendar_dry_run",
        "original_request": original,
        "parsed": {
            "title": title or "Untitled event",
            "date_hint": date_hint,
            "time_hint": time_hint,
            "duration_minutes": duration_minutes,
            "start_preview": start.isoformat(timespec="minutes"),
            "end_preview": end.isoformat(timespec="minutes")
        },
        "would_create_event": False,
        "safety_note": "Dry run only. No Calendar.app event was created."
    }


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: calendar_dry_run.py 'schedule meeting tomorrow at 3pm called dentist'", file=sys.stderr)
        return 2

    result = parse_request(" ".join(sys.argv[1:]))
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
