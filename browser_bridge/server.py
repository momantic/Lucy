#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import json, time
from pathlib import Path
from urllib.parse import parse_qs, urlparse

BRIDGE_VERSION = "0.2.0-targeted-linkedin"

STATE = {
    "last_page": "",
    "last_raw_page": "",
    "last_url": "",
    "last_title": "",
    "linkedin_posts": [],
    "updated_at": 0,
    "commands": []
}

def command_matches_url(command, page_url):
    """Return True when a queued command is intended for this tab/page.

    Older bridge commands had no target and should still be consumed by any tab.
    New LinkedIn reads include target_url_contains="linkedin.com" so random
    background tabs cannot consume the command before the LinkedIn tab sees it.
    """
    if not isinstance(command, dict):
        return True
    target = str(command.get("target_url_contains") or command.get("target_host") or "").lower().strip()
    if not target:
        return True
    return target in str(page_url or "").lower()

def pop_next_command(page_url=""):
    for index, command in enumerate(list(STATE["commands"])):
        if command_matches_url(command, page_url):
            return STATE["commands"].pop(index)
    return None

class Handler(BaseHTTPRequestHandler):
    def _send(self, obj):
        data = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.end_headers()
        self.wfile.write(data)

    def do_OPTIONS(self):
        self._send({"ok": True})

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path.startswith("/state"):
            self._send({"ok": True, **STATE})
        elif parsed.path.startswith("/next_command"):
            params = parse_qs(parsed.query)
            page_url = params.get("url", [""])[0]
            cmd = pop_next_command(page_url)
            self._send({"ok": True, "command": cmd})
        else:
            self._send({"ok": True, "service": "Lucy Browser Bridge", "version": BRIDGE_VERSION})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode()
        data = json.loads(body or "{}")

        if self.path.startswith("/page"):
            STATE["last_page"] = data.get("text", "")
            STATE["last_raw_page"] = data.get("rawText", "")
            STATE["last_url"] = data.get("url", "")
            STATE["last_title"] = data.get("title", "")
            posts = data.get("linkedinPosts", [])
            STATE["linkedin_posts"] = posts if isinstance(posts, list) else []
            STATE["updated_at"] = time.time()
            Path("/tmp/lucy_browser_page.txt").write_text(STATE["last_page"], encoding="utf-8")
            Path("/tmp/lucy_browser_raw_page.txt").write_text(STATE["last_raw_page"], encoding="utf-8")
            Path("/tmp/lucy_browser_linkedin_posts.json").write_text(json.dumps(STATE["linkedin_posts"], indent=2), encoding="utf-8")
            self._send({
                "ok": True,
                "words": len(STATE["last_page"].split()),
                "linkedin_posts": len(STATE["linkedin_posts"])
            })

        elif self.path.startswith("/command"):
            STATE["commands"].append(data)
            self._send({"ok": True, "queued": data})

        else:
            self._send({"ok": False, "error": "unknown route"})

if __name__ == "__main__":
    HTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
