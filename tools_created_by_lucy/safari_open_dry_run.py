#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from urllib.parse import urlparse


def normalize_url(value: str) -> str:
    value = value.strip()
    if not value:
        return ""

    if not re.match(r"^https?://", value, flags=re.IGNORECASE):
        value = "https://" + value

    return value


def parse_request(text: str) -> dict:
    original = text.strip()

    cleaned = re.sub(
        r"^\s*(open website|open safari to|open url|open link|go to website)\s+",
        "",
        original,
        flags=re.IGNORECASE,
    ).strip()

    url = normalize_url(cleaned)
    parsed = urlparse(url)

    valid = bool(parsed.scheme in {"http", "https"} and parsed.netloc)

    return {
        "dry_run": True,
        "tool": "safari_open_dry_run",
        "original_request": original,
        "parsed": {
            "url": url,
            "valid_url": valid
        },
        "would_open_safari": False,
        "safety_note": "Dry run only. Safari was not opened."
    }


def main() -> int:
    if len(sys.argv) < 2:
        print('Usage: safari_open_dry_run.py "open website https://example.com"', file=sys.stderr)
        return 2

    result = parse_request(" ".join(sys.argv[1:]))
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
