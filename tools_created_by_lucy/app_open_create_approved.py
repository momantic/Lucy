#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
from urllib.parse import quote_plus

from app_open_dry_run import parse_app_name, find_app


def main() -> int:
    if len(sys.argv) < 2:
        print('Usage: app_open_create_approved.py "open Roblox"', file=sys.stderr)
        return 2

    request = " ".join(sys.argv[1:])
    app_name = parse_app_name(request)
    app_path = find_app(app_name)

    if app_path:
        proc = subprocess.run(
            ["/usr/bin/open", app_path],
            text=True,
            capture_output=True,
            timeout=20,
        )

        if proc.returncode != 0:
            print(json.dumps({
                "created": False,
                "tool": "app_open_create_approved",
                "app_name": app_name,
                "app_path": app_path,
                "error": proc.stderr.strip() or proc.stdout.strip() or "open command failed",
                "safety_note": "App may not have opened."
            }, indent=2, ensure_ascii=False))
            return 1

        print(json.dumps({
            "created": True,
            "tool": "app_open_create_approved",
            "action": "opened_installed_app",
            "app_name": app_name,
            "app_path": app_path,
            "safety_note": "Opened installed app only after explicit approval."
        }, indent=2, ensure_ascii=False))
        return 0

    # Do NOT silently install. Open a search page after approval.
    query = quote_plus(f"{app_name} official download Mac")
    url = f"https://www.google.com/search?q={query}"

    proc = subprocess.run(
        ["/usr/bin/open", url],
        text=True,
        capture_output=True,
        timeout=20,
    )

    if proc.returncode != 0:
        print(json.dumps({
            "created": False,
            "tool": "app_open_create_approved",
            "app_name": app_name,
            "error": proc.stderr.strip() or proc.stdout.strip() or "open search failed",
            "safety_note": "No app was installed."
        }, indent=2, ensure_ascii=False))
        return 1

    print(json.dumps({
        "created": True,
        "tool": "app_open_create_approved",
        "action": "opened_download_search",
        "app_name": app_name,
        "url": url,
        "safety_note": "App was not installed silently. Opened a web search for the official Mac download route after approval."
    }, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
