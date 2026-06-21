#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timedelta
# LUCY_TODAY_GUARD: always resolve relative dates from real local system date, timedelta


DEFAULT_HOUR = 9
DEFAULT_MINUTE = 0


def parse_time(text: str) -> tuple[int, int, str | None]:
    m = re.search(r"\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b", text, flags=re.IGNORECASE)
    if not m:
        return DEFAULT_HOUR, DEFAULT_MINUTE, "No time found; defaulting to 9:00 AM."

    hour = int(m.group(1))
    minute = int(m.group(2) or "0")
    ampm = (m.group(3) or "").lower()

    if ampm == "pm" and hour != 12:
        hour += 12
    elif ampm == "am" and hour == 12:
        hour = 0

    return hour, minute, None


def parse_date(text: str) -> tuple[datetime, str]:
    now = datetime.now()
    lowered = text.lower()

    if "tomorrow" in lowered or "tmrw" in lowered or "tmr" in lowered:
        return now + timedelta(days=1), "tomorrow"

    if "today" in lowered:
        return now, "today"

    # If no date is found, default to tomorrow to avoid creating an immediate reminder.
    return now + timedelta(days=1), "No date found; defaulting to tomorrow."


def parse_title(text: str) -> str:
    title = text.strip()

    title = re.sub(r"^\s*remind me\s*", "", title, flags=re.IGNORECASE).strip()
    title = re.sub(r"^\s*to\s+", "", title, flags=re.IGNORECASE).strip()
    title = re.sub(r"\b(today|tomorrow|tmrw|tmr)\b", "", title, flags=re.IGNORECASE).strip()
    title = re.sub(r"\bat\s+\d{1,2}(?::\d{2})?\s*(am|pm)?\b", "", title, flags=re.IGNORECASE).strip()
    title = re.sub(r"\s+", " ", title).strip()

    return title or "Reminder"


def parse_request(text: str) -> dict:
    original = text.strip()

    date_base, date_note = parse_date(original)
    hour, minute, time_note = parse_time(original)

    due = date_base.replace(hour=hour, minute=minute, second=0, microsecond=0)
    title = parse_title(original)

    notes = []
    if date_note.startswith("No date"):
        notes.append(date_note)
    if time_note:
        notes.append(time_note)

    return {
        "dry_run": True,
        "tool": "reminders_dry_run",
        "original_request": original,
        "parsed": {
            "title": title,
            "due_iso": due.isoformat(),
            "due_preview": due.strftime("%Y-%m-%d %I:%M %p"),
            "assumptions": notes
        },
        "would_create_reminder": False,
        "safety_note": "Dry run only. No Reminders.app item was created."
    }


def main() -> int:
    if len(sys.argv) < 2:
        print('Usage: reminders_dry_run.py "remind me to workout tomorrow"', file=sys.stderr)
        return 2

    result = parse_request(" ".join(sys.argv[1:]))
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
