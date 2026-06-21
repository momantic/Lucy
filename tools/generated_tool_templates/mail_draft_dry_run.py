#!/usr/bin/env /usr/local/bin/python3
from __future__ import annotations

import json
import re
import sys


def parse_request(text: str) -> dict:
    original = text.strip()
    to = ""
    subject = "No subject"
    body = original

    m = re.search(
        r"(?:write|draft|create)\s+(?:an\s+)?email\s+to\s+(\S+)(?:\s+subject\s+(.+?))?(?:\s+saying\s+(.+))?$",
        original,
        flags=re.IGNORECASE,
    )

    if m:
        to = m.group(1).strip()
        if m.group(2):
            subject = m.group(2).strip()
        if m.group(3):
            body = m.group(3).strip()
    else:
        body = re.sub(r"^\s*(write|draft|create)\s+(an\s+)?email\s*", "", original, flags=re.IGNORECASE).strip()

    return {
        "dry_run": True,
        "tool": "mail_draft_dry_run",
        "original_request": original,
        "parsed": {
            "to": to,
            "subject": subject,
            "body": body
        },
        "would_create_draft": False,
        "safety_note": "Dry run only. No Mail.app draft was created."
    }


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: mail_draft_dry_run.py 'write an email to johndoe@example.com subject Hello saying testing Lucy mail draft'", file=sys.stderr)
        return 2

    result = parse_request(" ".join(sys.argv[1:]))
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
