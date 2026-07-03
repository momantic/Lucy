#!/usr/bin/env python3
"""Small CLI/client for Lucy's local browser bridge.

The Chrome extension posts visible page text to the local bridge server. This
module intentionally has no import-time side effects so it can be tested, and
the CLI starts the bridge server on demand before requesting page state.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path
from urllib.error import URLError


BASE = os.environ.get("LUCY_BROWSER_BRIDGE_URL", "http://127.0.0.1:8765")
EXPECTED_BRIDGE_VERSION = "0.2.0-targeted-linkedin"
ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "browser_bridge" / "server.py"
CACHE_PATH = Path("/tmp/lucy_browser_page.txt")
LINKEDIN_POSTS_PATH = Path("/tmp/lucy_browser_linkedin_posts.json")
SERVER_LOG = Path("/tmp/lucy_browser_bridge.log")
SERVER_ERR = Path("/tmp/lucy_browser_bridge.err.log")


class BridgeUnavailable(RuntimeError):
    """Raised when the local browser bridge cannot be reached."""


def get(path: str, timeout: float = 5):
    return json.loads(urllib.request.urlopen(BASE + path, timeout=timeout).read())


def post(path: str, obj, timeout: float = 5):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(obj).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    return json.loads(urllib.request.urlopen(req, timeout=timeout).read())


def bridge_status() -> dict:
    try:
        status = get("/", timeout=0.4)
        return status if isinstance(status, dict) else {}
    except Exception:
        return {}


def bridge_available() -> bool:
    status = bridge_status()
    return status.get("service") == "Lucy Browser Bridge" and status.get("version") == EXPECTED_BRIDGE_VERSION


def stop_stale_bridge_server() -> None:
    """Stop an older local bridge process if it is occupying port 8765."""
    status = bridge_status()
    if not status or status.get("version") == EXPECTED_BRIDGE_VERSION:
        return

    try:
        proc = subprocess.run(
            ["/usr/sbin/lsof", "-ti", "tcp:8765"],
            text=True,
            capture_output=True,
            timeout=2,
        )
    except Exception:
        return

    pids = [pid.strip() for pid in proc.stdout.splitlines() if pid.strip().isdigit()]
    for pid in pids:
        subprocess.run(["/bin/kill", pid], check=False)
    if pids:
        time.sleep(0.5)


def bridge_port_occupied_by_stale_server() -> bool:
    status = bridge_status()
    if not status:
        return False
    return status.get("version") != EXPECTED_BRIDGE_VERSION


def start_bridge_server() -> bool:
    """Start the local server if it is not already running."""
    if bridge_available():
        return True
    if bridge_port_occupied_by_stale_server():
        stop_stale_bridge_server()
        if bridge_available():
            return True
    if not SERVER.exists():
        return False

    out = SERVER_LOG.open("a", encoding="utf-8")
    err = SERVER_ERR.open("a", encoding="utf-8")
    subprocess.Popen(
        [sys.executable, str(SERVER)],
        cwd=str(ROOT),
        stdout=out,
        stderr=err,
        start_new_session=True,
    )
    out.close()
    err.close()
    for _ in range(20):
        if bridge_available():
            return True
        time.sleep(0.15)
    return False


def ensure_bridge_server() -> None:
    if not start_bridge_server():
        raise BridgeUnavailable(
            "Lucy Browser Bridge server is not reachable at "
            f"{BASE}. Start it with: python3 {SERVER}"
        )


def open_url(url: str) -> str:
    subprocess.run(["open", "-a", "Google Chrome", url], check=False)
    return url


def linkedin_search(topic: str, wait_seconds: float = 5):
    ensure_bridge_server()
    q = urllib.parse.quote(topic)
    url = f"https://www.linkedin.com/search/results/content/?keywords={q}"
    open_url(url)
    time.sleep(wait_seconds)
    return read_page(wait_seconds=1.5, target_url_contains="linkedin.com")


def state():
    ensure_bridge_server()
    return get("/state")


def read_page(wait_seconds: float = 1.5, target_url_contains: str | None = None):
    """Ask the extension/content script to capture the current page now.

    The previous implementation only returned stale server state. Queueing a
    `read_page` command makes the extension poller call `sendPage()` again, so
    Lucy reads the current LinkedIn results after navigation/search.
    """
    ensure_bridge_server()
    command = {"type": "read_page"}
    if target_url_contains:
        command["target_url_contains"] = target_url_contains
    post("/command", command)
    if wait_seconds > 0:
        time.sleep(wait_seconds)
    return get("/state")


def page_text() -> str:
    ensure_bridge_server()
    try:
        text = get("/state").get("last_page", "")
    except Exception:
        text = ""
    if text.strip():
        return text
    if CACHE_PATH.exists():
        return CACHE_PATH.read_text(encoding="utf-8", errors="ignore")
    return ""


def linkedin_posts_text() -> str:
    """Return a clean digest of structured LinkedIn posts captured by the extension."""
    ensure_bridge_server()
    posts = []
    try:
        state_posts = get("/state").get("linkedin_posts", [])
        if isinstance(state_posts, list):
            posts = state_posts
    except Exception:
        posts = []
    if not posts and LINKEDIN_POSTS_PATH.exists():
        try:
            cached = json.loads(LINKEDIN_POSTS_PATH.read_text(encoding="utf-8", errors="ignore"))
            if isinstance(cached, list):
                posts = cached
        except Exception:
            posts = []
    if not posts:
        return ""

    blocks = ["LinkedIn top visible posts captured from the current page:"]
    for idx, post in enumerate(posts[:8], start=1):
        lines = [f"Post {idx}"]
        for label, key in [("Author", "author"), ("Headline", "headline"), ("URL", "url"), ("Engagement text", "engagement")]:
            value = str(post.get(key, "")).strip() if isinstance(post, dict) else ""
            if value:
                lines.append(f"{label}: {value}")
        text = str(post.get("text", "")).strip() if isinstance(post, dict) else ""
        if text:
            lines.extend(["Text:", text])
        blocks.append("\n".join(lines))
    return "\n\n---\n\n".join(blocks)


def main(argv=None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    cmd = args[0] if args else "state"
    rest = " ".join(args[1:])

    try:
        if cmd == "open":
            print("Opened:", open_url(rest))
        elif cmd == "linkedin_search":
            print("Opened LinkedIn search:", rest)
            print(json.dumps(linkedin_search(rest), indent=2)[:4000])
        elif cmd == "read":
            target = "linkedin.com" if rest.lower() in {"linkedin", "linkedin.com"} else None
            print(json.dumps(read_page(target_url_contains=target), indent=2)[:8000])
        elif cmd == "page_text":
            print(page_text())
        elif cmd == "linkedin_posts_text":
            print(linkedin_posts_text())
        elif cmd == "start":
            ensure_bridge_server()
            print(json.dumps({"ok": True, "service": "Lucy Browser Bridge", "url": BASE, "version": EXPECTED_BRIDGE_VERSION}, indent=2))
        else:
            print(json.dumps(state(), indent=2))
        return 0
    except (BridgeUnavailable, URLError, TimeoutError, OSError) as exc:
        print(json.dumps({"ok": False, "error": str(exc), "url": BASE}, indent=2), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
