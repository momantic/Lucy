#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from urllib.parse import quote_plus


def main() -> int:
    query = " ".join(sys.argv[1:]).strip()
    if not query:
        print(json.dumps({"ok": False, "error": "Usage: public_web_search.py <query>"}))
        return 2

    url = "https://www.google.com/search?q=" + quote_plus(query)

    print(json.dumps({
        "ok": True,
        "tool": "public_web_search",
        "query": query,
        "search_url": url,
        "note": "This V1 dynamic tool returns a safe public search URL. It does not scrape private/authenticated sites."
    }, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
