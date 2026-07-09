#!/usr/bin/env python3
"""Private Lucy download tracker.

Run this on a small public server and point Lucy's download links at `/d/lucy`.
It records a lightweight download event in SQLite, redirects the visitor to the
real GitHub release ZIP, and exposes a token-protected real-time dashboard.

Environment variables:
  LUCY_TRACKER_TOKEN       Secret token required for /dashboard, /api/stats,
                           and /api/events. Defaults to "change-me".
  LUCY_TRACKER_DB          SQLite database path. Defaults to
                           data/download_tracker.sqlite3.
  LUCY_DOWNLOAD_URL        Final ZIP URL. Defaults to Lucy's latest release ZIP.
  LUCY_TRACKER_HOST        Host to bind. Defaults to 127.0.0.1.
  LUCY_TRACKER_PORT        Port to bind. Defaults to 8787.
  LUCY_TRACKER_HASH_SALT   Optional salt for anonymized IP hashes.
"""

from __future__ import annotations

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hashlib
import html
import json
import os
from pathlib import Path
import sqlite3
import time
from typing import Any
from urllib.parse import parse_qs, urlencode, urlparse


DEFAULT_DOWNLOAD_URL = "https://github.com/momantic/Lucy/releases/latest/download/Lucy-v0.1-beta.zip"
DEFAULT_DB_PATH = Path(__file__).resolve().parents[1] / "data" / "download_tracker.sqlite3"

TRACKER_TOKEN = os.environ.get("LUCY_TRACKER_TOKEN", "change-me")
DOWNLOAD_URL = os.environ.get("LUCY_DOWNLOAD_URL", DEFAULT_DOWNLOAD_URL)
DB_PATH = Path(os.environ.get("LUCY_TRACKER_DB", str(DEFAULT_DB_PATH))).expanduser()
HASH_SALT = os.environ.get("LUCY_TRACKER_HASH_SALT", "lucy-download-tracker")


def db_connect() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    with db_connect() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS download_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at INTEGER NOT NULL,
                source TEXT NOT NULL,
                referrer TEXT NOT NULL,
                user_agent TEXT NOT NULL,
                ip_hash TEXT NOT NULL
            )
            """
        )
        conn.execute("CREATE INDEX IF NOT EXISTS idx_download_events_created_at ON download_events(created_at)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_download_events_source ON download_events(source)")


def safe_text(value: str, max_len: int = 500) -> str:
    value = str(value or "").strip()
    return value[:max_len]


def client_ip(handler: BaseHTTPRequestHandler) -> str:
    forwarded = handler.headers.get("X-Forwarded-For", "")
    if forwarded:
        return forwarded.split(",", 1)[0].strip()
    return handler.client_address[0] if handler.client_address else ""


def anonymize_ip(ip: str) -> str:
    digest = hashlib.sha256(f"{HASH_SALT}:{ip}".encode("utf-8")).hexdigest()
    return digest[:24]


def record_download(handler: BaseHTTPRequestHandler, source: str) -> int:
    now = int(time.time())
    with db_connect() as conn:
        cursor = conn.execute(
            """
            INSERT INTO download_events (created_at, source, referrer, user_agent, ip_hash)
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                now,
                safe_text(source or "unknown", 80),
                safe_text(handler.headers.get("Referer", ""), 500),
                safe_text(handler.headers.get("User-Agent", ""), 500),
                anonymize_ip(client_ip(handler)),
            ),
        )
        return int(cursor.lastrowid)


def fetch_stats() -> dict[str, Any]:
    now = int(time.time())
    today_start = now - (now % 86400)
    hour_start = now - 3600

    with db_connect() as conn:
        total = conn.execute("SELECT COUNT(*) FROM download_events").fetchone()[0]
        today = conn.execute("SELECT COUNT(*) FROM download_events WHERE created_at >= ?", (today_start,)).fetchone()[0]
        last_hour = conn.execute("SELECT COUNT(*) FROM download_events WHERE created_at >= ?", (hour_start,)).fetchone()[0]
        unique_total = conn.execute("SELECT COUNT(DISTINCT ip_hash) FROM download_events").fetchone()[0]
        by_source = [
            dict(row)
            for row in conn.execute(
                """
                SELECT source, COUNT(*) AS count
                FROM download_events
                GROUP BY source
                ORDER BY count DESC, source ASC
                LIMIT 20
                """
            )
        ]
        recent = [
            dict(row)
            for row in conn.execute(
                """
                SELECT id, created_at, source, referrer, user_agent
                FROM download_events
                ORDER BY id DESC
                LIMIT 25
                """
            )
        ]

    return {
        "ok": True,
        "generated_at": now,
        "total": total,
        "today": today,
        "last_hour": last_hour,
        "unique_total": unique_total,
        "by_source": by_source,
        "recent": recent,
    }


def token_from_request(parsed_query: dict[str, list[str]], headers: Any) -> str:
    auth = headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        return auth.removeprefix("Bearer ").strip()
    return parsed_query.get("token", [""])[0]


def authorized(parsed_query: dict[str, list[str]], headers: Any) -> bool:
    return token_from_request(parsed_query, headers) == TRACKER_TOKEN


def dashboard_html(token: str) -> bytes:
    escaped_token = html.escape(token, quote=True)
    return f"""<!doctype html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
<title>Lucy Download Tracker</title>
<style>
:root{{color-scheme:dark;--bg:#080812;--panel:rgba(255,255,255,.07);--line:rgba(255,255,255,.14);--muted:rgba(255,255,255,.7);--cyan:#00d4ff;--violet:#7c5cff;--green:#6dffb2}}*{{box-sizing:border-box}}body{{margin:0;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display","Segoe UI",sans-serif;background:radial-gradient(circle at 15% 0%,rgba(124,92,255,.28),transparent 35%),linear-gradient(180deg,#101026,var(--bg));color:white}}main{{max-width:1100px;margin:0 auto;padding:34px 22px 70px}}.top{{display:flex;align-items:end;justify-content:space-between;gap:18px;flex-wrap:wrap}}h1{{font-size:clamp(36px,6vw,68px);letter-spacing:-.06em;line-height:.94;margin:18px 0;background:linear-gradient(90deg,#fff,#d7d9ff 45%,var(--cyan));-webkit-background-clip:text;-webkit-text-fill-color:transparent}}.pill{{display:inline-flex;border:1px solid rgba(109,255,178,.28);background:rgba(109,255,178,.09);color:var(--green);border-radius:999px;padding:7px 12px;font-weight:800;font-size:13px}}.grid{{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin:26px 0}}.card{{background:var(--panel);border:1px solid var(--line);border-radius:20px;padding:18px}}.num{{font-size:38px;font-weight:950;letter-spacing:-.04em}}.label{{color:var(--muted);font-size:14px}}table{{width:100%;border-collapse:collapse;overflow:hidden;border-radius:16px}}th,td{{text-align:left;padding:12px;border-bottom:1px solid rgba(255,255,255,.09);vertical-align:top}}th{{color:var(--muted);font-size:13px}}.muted{{color:var(--muted)}}.status{{font-size:13px;color:var(--muted)}}@media(max-width:760px){{.grid{{grid-template-columns:1fr 1fr}}table{{font-size:13px}}}}
</style>
</head>
<body>
<main>
  <div class=\"top\"><div><span class=\"pill\">private realtime dashboard</span><h1>Lucy downloads</h1></div><div class=\"status\" id=\"status\">Connecting…</div></div>
  <section class=\"grid\">
    <div class=\"card\"><div class=\"num\" id=\"total\">0</div><div class=\"label\">total downloads</div></div>
    <div class=\"card\"><div class=\"num\" id=\"today\">0</div><div class=\"label\">today</div></div>
    <div class=\"card\"><div class=\"num\" id=\"last_hour\">0</div><div class=\"label\">last hour</div></div>
    <div class=\"card\"><div class=\"num\" id=\"unique_total\">0</div><div class=\"label\">unique devices/IPs</div></div>
  </section>
  <section class=\"card\"><h2>Sources</h2><div id=\"sources\" class=\"muted\">No downloads yet.</div></section>
  <section class=\"card\" style=\"margin-top:14px\"><h2>Recent downloads</h2><table><thead><tr><th>Time</th><th>Source</th><th>Referrer</th><th>User agent</th></tr></thead><tbody id=\"recent\"></tbody></table></section>
</main>
<script>
const token = "{escaped_token}";
const fmt = new Intl.NumberFormat();
const statusEl = document.getElementById('status');
function text(id, value) {{ document.getElementById(id).textContent = fmt.format(value || 0); }}
function render(data) {{
  text('total', data.total); text('today', data.today); text('last_hour', data.last_hour); text('unique_total', data.unique_total);
  document.getElementById('sources').innerHTML = (data.by_source || []).length ? '<table><tbody>' + data.by_source.map(row => `<tr><td>${{escapeHtml(row.source)}}</td><td>${{fmt.format(row.count)}}</td></tr>`).join('') + '</tbody></table>' : 'No downloads yet.';
  document.getElementById('recent').innerHTML = (data.recent || []).map(row => `<tr><td>${{new Date(row.created_at * 1000).toLocaleString()}}</td><td>${{escapeHtml(row.source)}}</td><td class=\"muted\">${{escapeHtml(row.referrer || '')}}</td><td class=\"muted\">${{escapeHtml(row.user_agent || '')}}</td></tr>`).join('');
  statusEl.textContent = 'Updated ' + new Date((data.generated_at || Date.now()/1000) * 1000).toLocaleTimeString();
}}
function escapeHtml(value) {{ return String(value || '').replace(/[&<>\"]/g, ch => ({{'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;'}}[ch])); }}
async function poll() {{
  const res = await fetch('/api/stats?token=' + encodeURIComponent(token), {{cache: 'no-store'}});
  render(await res.json());
}}
try {{
  const events = new EventSource('/api/events?token=' + encodeURIComponent(token));
  events.onmessage = event => render(JSON.parse(event.data));
  events.onerror = () => {{ statusEl.textContent = 'Realtime reconnecting…'; }};
}} catch (error) {{ setInterval(poll, 2500); }}
poll().catch(() => {{ statusEl.textContent = 'Could not load stats.'; }});
</script>
</body>
</html>""".encode("utf-8")


class DownloadTrackerHandler(BaseHTTPRequestHandler):
    server_version = "LucyDownloadTracker/1.0"

    def _send_json(self, obj: dict[str, Any], status: int = 200) -> None:
        data = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

    def _send_html(self, data: bytes, status: int = 200) -> None:
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _redirect(self, location: str) -> None:
        self.send_response(302)
        self.send_header("Location", location)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.end_headers()

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)

        if parsed.path in {"/d/lucy", "/download/lucy"}:
            source = params.get("source", ["unknown"])[0]
            event_id = record_download(self, source)
            query = {"lucy_download_event": event_id}
            separator = "&" if "?" in DOWNLOAD_URL else "?"
            self._redirect(f"{DOWNLOAD_URL}{separator}{urlencode(query)}")
            return

        if parsed.path == "/api/stats":
            if not authorized(params, self.headers):
                self._send_json({"ok": False, "error": "unauthorized"}, 401)
                return
            self._send_json(fetch_stats())
            return

        if parsed.path == "/api/events":
            if not authorized(params, self.headers):
                self._send_json({"ok": False, "error": "unauthorized"}, 401)
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            last_payload = ""
            try:
                for _ in range(3600):
                    payload = json.dumps(fetch_stats())
                    if payload != last_payload:
                        self.wfile.write(f"data: {payload}\n\n".encode("utf-8"))
                        self.wfile.flush()
                        last_payload = payload
                    time.sleep(1)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return

        if parsed.path in {"/", "/dashboard"}:
            if not authorized(params, self.headers):
                self._send_html(b"Unauthorized. Open /dashboard?token=YOUR_TOKEN", 401)
                return
            self._send_html(dashboard_html(token_from_request(params, self.headers)))
            return

        self._send_json({"ok": True, "service": "Lucy Download Tracker", "download_path": "/d/lucy"})


def main() -> None:
    init_db()
    host = os.environ.get("LUCY_TRACKER_HOST", "127.0.0.1")
    port = int(os.environ.get("LUCY_TRACKER_PORT", "8787"))
    if TRACKER_TOKEN == "change-me":
        print("WARNING: set LUCY_TRACKER_TOKEN before exposing this server publicly.")
    print(f"Lucy download tracker listening on http://{host}:{port}")
    print(f"Dashboard: http://{host}:{port}/dashboard?token={TRACKER_TOKEN}")
    ThreadingHTTPServer((host, port), DownloadTrackerHandler).serve_forever()


if __name__ == "__main__":
    main()