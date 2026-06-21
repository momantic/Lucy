#!/usr/bin/env /usr/local/bin/python3
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
TOOLS_DIR = PROJECT_ROOT / "tools_created_by_lucy"
REGISTRY = TOOLS_DIR / "tool_registry.json"

PAIR_BASE = "web_app_search"
DRY_NAME = "web_app_search_dry_run"
APPROVED_NAME = "web_app_search_create_approved"

INTENT_PREFIXES = [
    "find ",
    "find me ",
    "search ",
    "search for ",
    "look up ",
    "play ",
]

DRY_RUN_CODE = r'''#!/usr/bin/env /usr/local/bin/python3
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
'''

APPROVED_CODE = r'''#!/usr/bin/env /usr/local/bin/python3
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
'''


def load_registry() -> dict:
    TOOLS_DIR.mkdir(parents=True, exist_ok=True)
    if not REGISTRY.exists():
        return {"tools": []}
    raw = REGISTRY.read_text().strip()
    if not raw:
        return {"tools": []}
    return json.loads(raw)


def save_registry(data: dict) -> None:
    REGISTRY.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def add_or_replace(data: dict, entry: dict) -> None:
    tools = data.setdefault("tools", [])
    by_name = {t.get("name"): t for t in tools}
    by_name[entry["name"]] = entry
    data["tools"] = list(by_name.values())


def create_web_app_search_tool() -> None:
    dry_path = TOOLS_DIR / f"{DRY_NAME}.py"
    approved_path = TOOLS_DIR / f"{APPROVED_NAME}.py"

    dry_path.write_text(DRY_RUN_CODE)
    approved_path.write_text(APPROVED_CODE)
    dry_path.chmod(0o755)
    approved_path.chmod(0o755)

    for path in [dry_path, approved_path]:
        proc = subprocess.run(
            ["/usr/local/bin/python3", "-m", "py_compile", str(path)],
            cwd=str(PROJECT_ROOT),
            text=True,
            capture_output=True,
            timeout=30,
        )
        if proc.returncode != 0:
            raise RuntimeError(proc.stderr or proc.stdout)

    data = load_registry()
    add_or_replace(data, {
        "name": DRY_NAME,
        "path": f"tools_created_by_lucy/{DRY_NAME}.py",
        "status": "sandbox",
        "dry_run": True,
        "pair_base": PAIR_BASE,
        "role": "dry_run",
        "intent_prefixes": INTENT_PREFIXES,
        "purpose": "Search Spotify, YouTube, or Google from natural search requests.",
        "requires_approval_for_real_action": True,
        "smoke_test": '/usr/local/bin/python3 tools_created_by_lucy/web_app_search_dry_run.py "find me never gonna give you up on spotify"'
    })
    add_or_replace(data, {
        "name": APPROVED_NAME,
        "path": f"tools_created_by_lucy/{APPROVED_NAME}.py",
        "status": "sandbox",
        "dry_run": False,
        "pair_base": PAIR_BASE,
        "role": "create_approved",
        "intent_prefixes": INTENT_PREFIXES,
        "purpose": "Open Spotify, YouTube, or Google search results after approval.",
        "requires_approval_for_real_action": True,
        "smoke_test": '/usr/local/bin/python3 tools_created_by_lucy/web_app_search_create_approved.py "find me never gonna give you up on spotify"'
    })
    save_registry(data)


def run_dry_run(request: str) -> str:
    proc = subprocess.run(
        ["/usr/local/bin/python3", str(TOOLS_DIR / f"{DRY_NAME}.py"), request],
        cwd=str(PROJECT_ROOT),
        text=True,
        capture_output=True,
        timeout=30,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr or proc.stdout)
    return proc.stdout.strip()


def main() -> int:
    if len(sys.argv) < 2:
        print(json.dumps({"ok": False, "error": "Usage: lucy_capability_author.py '<request>'"}, indent=2))
        return 2

    request = " ".join(sys.argv[1:]).strip()

    create_web_app_search_tool()
    dry = run_dry_run(request)

    print(json.dumps({
        "ok": True,
        "mode": "capability_author_created_or_updated_tool",
        "pair_base": PAIR_BASE,
        "dry_run_tool": DRY_NAME,
        "approved_tool": APPROVED_NAME,
        "request": request,
        "dry_run_output": dry,
        "needs_approval": True,
        "approval_instruction": "Say 'yes create it' to run the approved action."
    }, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
