#!/usr/bin/env python3
"""
Lucy-created tool: notes_dry_run.py

Purpose:
Parse a simple note creation request and print a safe preview.

Dry-run only. It does not create real Notes.app notes.
"""

from __future__ import annotations

import json
import re
import sys


def parse_request(text: str) -> dict:
    original = text.strip()

    title = "Untitled Note"
    body = original

    # Patterns:
    # create a note called X saying Y
    # make a note titled X: Y
    m = re.search(
        r"(?:create|make|add)\s+(?:a\s+)?note\s+(?:called|named|titled)\s+(.+?)\s+(?:saying|with|that says)\s+(.+)$",
        original,
        flags=re.IGNORECASE,
    )
    if m:
        title = m.group(1).strip()
        body = m.group(2).strip()
    else:
        m = re.search(
            r"(?:create|make|add)\s+(?:a\s+)?note\s+(?:called|named|titled)\s+(.+)$",
            original,
            flags=re.IGNORECASE,
        )
        if m:
            title = m.group(1).strip()
            body = ""
        else:
            body = re.sub(r"^\s*(create|make|add)\s+(a\s+)?note\s*", "", original, flags=re.IGNORECASE).strip()

    title = re.sub(r"\s+", " ", title).strip() or "Untitled Note"
    body = body.strip()

    return {
        "dry_run": True,
        "tool": "notes_dry_run",
        "original_request": original,
        "parsed": {
            "title": title,
            "body": body
        },
        "would_create_note": False,
        "safety_note": "Dry run only. No Notes.app note was created."
    }


def main() -> int:
    if len(sys.argv) < 2:
        print('Usage: notes_dry_run.py "create a note called Lucy ideas saying add better spider animations"', file=sys.stderr)
        return 2

    result = parse_request(" ".join(sys.argv[1:]))
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
