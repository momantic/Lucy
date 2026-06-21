#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import json, time
from pathlib import Path

STATE = {
    "last_page": "",
    "last_url": "",
    "last_title": "",
    "updated_at": 0,
    "commands": []
}

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
        if self.path.startswith("/state"):
            self._send({"ok": True, **STATE})
        elif self.path.startswith("/next_command"):
            cmd = STATE["commands"].pop(0) if STATE["commands"] else None
            self._send({"ok": True, "command": cmd})
        else:
            self._send({"ok": True, "service": "Lucy Browser Bridge"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode()
        data = json.loads(body or "{}")

        if self.path.startswith("/page"):
            STATE["last_page"] = data.get("text", "")
            STATE["last_url"] = data.get("url", "")
            STATE["last_title"] = data.get("title", "")
            STATE["updated_at"] = time.time()
            Path("/tmp/lucy_browser_page.txt").write_text(STATE["last_page"], encoding="utf-8")
            self._send({"ok": True, "words": len(STATE["last_page"].split())})

        elif self.path.startswith("/command"):
            STATE["commands"].append(data)
            self._send({"ok": True, "queued": data})

        else:
            self._send({"ok": False, "error": "unknown route"})

HTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
