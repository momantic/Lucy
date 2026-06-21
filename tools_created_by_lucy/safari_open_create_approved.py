#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys

from safari_open_dry_run import parse_request


def main() -> int:
    if len(sys.argv) < 2:
        print('Usage: safari_open_create_approved.py "open website https://example.com"', file=sys.stderr)
        return 2

    request = " ".join(sys.argv[1:])
    parsed = parse_request(request)
    info = parsed["parsed"]

    if not info.get("valid_url"):
        print(json.dumps({
            "created": False,
            "tool": "safari_open_create_approved",
            "error": "Invalid URL.",
            "parsed": info,
            "safety_note": "Safari was not opened because URL validation failed."
        }, indent=2, ensure_ascii=False))
        return 1

    url = info["url"]

    proc = subprocess.run(
        ["/usr/bin/open", "-a", "Safari", url],
        text=True,
        capture_output=True,
        timeout=15,
    )

    if proc.returncode != 0:
        print(json.dumps({
            "created": False,
            "tool": "safari_open_create_approved",
            "url": url,
            "error": proc.stderr.strip() or proc.stdout.strip() or "open command failed",
            "safety_note": "Safari may not have opened."
        }, indent=2, ensure_ascii=False))
        return 1

    print(json.dumps({
        "created": True,
        "tool": "safari_open_create_approved",
        "url": url,
        "safety_note": "Opened Safari only after explicit approval."
    }, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
