#!/usr/bin/env /usr/local/bin/python3
from __future__ import annotations

import json
import subprocess
import sys
from urllib.parse import quote_plus

from web_app_search_dry_run import parse_request


def main() -> int:
    if len(sys.argv) < 2:
        print('Usage: web_app_search_create_approved.py "find me never gonna give you up on spotify"', file=sys.stderr)
        return 2

    request = " ".join(sys.argv[1:])
    parsed = parse_request(request)
    info = parsed["parsed"]
    target = info["target"]
    query = info["query"]

    if not query:
        print(json.dumps({
            "created": False,
            "tool": "web_app_search_create_approved",
            "error": "Empty search query.",
            "safety_note": "Nothing was opened."
        }, indent=2, ensure_ascii=False))
        return 1

    q = quote_plus(query)

    if target == "spotify":
        url = f"https://open.spotify.com/search/{q}"
    elif target == "youtube":
        url = f"https://www.youtube.com/results?search_query={q}"
    else:
        url = f"https://www.google.com/search?q={q}"

    proc = subprocess.run(
        ["/usr/bin/open", url],
        text=True,
        capture_output=True,
        timeout=20,
    )

    if proc.returncode != 0:
        print(json.dumps({
            "created": False,
            "tool": "web_app_search_create_approved",
            "target": target,
            "query": query,
            "url": url,
            "error": proc.stderr.strip() or proc.stdout.strip() or "open command failed"
        }, indent=2, ensure_ascii=False))
        return 1

    print(json.dumps({
        "created": True,
        "tool": "web_app_search_create_approved",
        "target": target,
        "query": query,
        "url": url,
        "safety_note": "Opened search results only after explicit approval."
    }, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
