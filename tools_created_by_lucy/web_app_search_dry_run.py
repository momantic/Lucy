#!/usr/bin/env /usr/local/bin/python3
from __future__ import annotations

import json
import re
import sys


def parse_request(text: str) -> dict:
    original = text.strip()
    lowered = original.lower()

    target = "google"
    if "spotify" in lowered:
        target = "spotify"
    elif "youtube" in lowered or "yt" in lowered:
        target = "youtube"

    query = original
    query = re.sub(r"^\s*(find me|find|search for|search|look up|play)\s+", "", query, flags=re.IGNORECASE)
    query = re.sub(r"\s+on\s+(spotify|youtube|google)\s*$", "", query, flags=re.IGNORECASE)
    query = query.strip()

    return {
        "dry_run": True,
        "tool": "web_app_search_dry_run",
        "original_request": original,
        "parsed": {
            "target": target,
            "query": query
        },
        "would_open_search": bool(query),
        "safety_note": "Dry run only. No browser or app was opened."
    }


def main() -> int:
    if len(sys.argv) < 2:
        print('Usage: web_app_search_dry_run.py "find me never gonna give you up on spotify"', file=sys.stderr)
        return 2

    result = parse_request(" ".join(sys.argv[1:]))
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
