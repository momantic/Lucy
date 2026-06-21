#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from html.parser import HTMLParser
from urllib.parse import urljoin
from urllib.request import Request, urlopen


class LinkParser(HTMLParser):
    def __init__(self, base_url: str):
        super().__init__()
        self.base_url = base_url
        self.links = []

    def handle_starttag(self, tag, attrs):
        if tag.lower() != "a":
            return
        href = None
        text = ""
        for key, value in attrs:
            if key.lower() == "href":
                href = value
        if href:
            self.links.append(urljoin(self.base_url, href))


def main() -> int:
    if len(sys.argv) < 2:
        print(json.dumps({"ok": False, "error": "Usage: extract_links.py <url>"}))
        return 2

    url = sys.argv[1].strip()
    if not (url.startswith("http://") or url.startswith("https://")):
        url = "https://" + url

    req = Request(url, headers={"User-Agent": "LucyDynamicTool/0.1"})
    with urlopen(req, timeout=8) as resp:
        html = resp.read().decode("utf-8", errors="replace")

    parser = LinkParser(url)
    parser.feed(html)

    print(json.dumps({
        "ok": True,
        "tool": "extract_links",
        "url": url,
        "links": sorted(set(parser.links))[:100]
    }, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
