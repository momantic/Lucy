#!/usr/bin/env /usr/local/bin/python3
from __future__ import annotations

import json
import subprocess
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
TOOLS_DIR = PROJECT_ROOT / "tools_created_by_lucy"
REGISTRY = TOOLS_DIR / "tool_registry.json"

INTENT_PREFIXES = [
    "open ",
    "launch ",
    "start ",
    "run ",
    "open app ",
    "launch app ",
]

DRY_RUN = '''#!/usr/bin/env /usr/local/bin/python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path


COMMON_APP_DIRS = [
    Path("/Applications"),
    Path.home() / "Applications",
]


def parse_app_name(text: str) -> str:
    original = text.strip()
    lowered = original.lower()

    prefixes = ["open app ", "launch app ", "open ", "launch ", "start ", "run "]

    for prefix in prefixes:
        if lowered.startswith(prefix):
            app = original[len(prefix):].strip()
            app = re.sub(r"\\s+for me\\s*$", "", app, flags=re.IGNORECASE).strip()
            app = re.sub(r"\\s+please\\s*$", "", app, flags=re.IGNORECASE).strip()
            return app

    return original


def find_app(app_name: str) -> str | None:
    candidates = []
    cleaned = app_name.strip()
    if not cleaned:
        return None

    if cleaned.lower().endswith(".app"):
        candidates.append(cleaned)
    else:
        candidates.append(cleaned + ".app")

    # Common normalization: roblox -> Roblox.app
    title = cleaned.title()
    if not title.lower().endswith(".app"):
        candidates.append(title + ".app")

    for app_dir in COMMON_APP_DIRS:
        for candidate in candidates:
            path = app_dir / candidate
            if path.exists():
                return str(path)

    # Fallback broad scan, limited to exact lowercase app bundle name match.
    wanted = {c.lower() for c in candidates}
    for app_dir in COMMON_APP_DIRS:
        if not app_dir.exists():
            continue
        for path in app_dir.glob("*.app"):
            if path.name.lower() in wanted:
                return str(path)

    return None


def main() -> int:
    if len(sys.argv) < 2:
        print('Usage: app_open_dry_run.py "open Roblox"', file=sys.stderr)
        return 2

    request = " ".join(sys.argv[1:])
    app_name = parse_app_name(request)
    app_path = find_app(app_name)

    installed = app_path is not None

    result = {
        "dry_run": True,
        "tool": "app_open_dry_run",
        "original_request": request,
        "parsed": {
            "app_name": app_name,
            "installed": installed,
            "app_path": app_path
        },
        "would_open_app": installed,
        "would_install_or_download": False,
        "missing_app_next_step": None,
        "safety_note": "Dry run only. No app was opened, downloaded, or installed."
    }

    if not installed:
        result["missing_app_next_step"] = (
            f"{app_name} was not found in /Applications or ~/Applications. "
            "Approved action will open a web search for the official download page; "
            "it will not install anything silently."
        )

    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'''

CREATE_APPROVED = '''#!/usr/bin/env /usr/local/bin/python3
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


def main() -> int:
    TOOLS_DIR.mkdir(parents=True, exist_ok=True)

    dry_path = TOOLS_DIR / "app_open_dry_run.py"
    approved_path = TOOLS_DIR / "app_open_create_approved.py"

    dry_path.write_text(DRY_RUN)
    approved_path.write_text(CREATE_APPROVED)
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
            print(proc.stderr or proc.stdout)
            return 1

    data = load_registry()

    add_or_replace(data, {
        "name": "app_open_dry_run",
        "path": "tools_created_by_lucy/app_open_dry_run.py",
        "status": "sandbox",
        "dry_run": True,
        "pair_base": "app_open",
        "role": "dry_run",
        "intent_prefixes": INTENT_PREFIXES,
        "purpose": "Parse app-opening requests, check whether the app is installed, and preview the action.",
        "requires_approval_for_real_action": True,
        "smoke_test": '/usr/local/bin/python3 tools_created_by_lucy/app_open_dry_run.py "open Roblox"'
    })

    add_or_replace(data, {
        "name": "app_open_create_approved",
        "path": "tools_created_by_lucy/app_open_create_approved.py",
        "status": "sandbox",
        "dry_run": False,
        "pair_base": "app_open",
        "role": "create_approved",
        "intent_prefixes": INTENT_PREFIXES,
        "purpose": "Open an installed app after approval, or open a safe download search page if missing.",
        "requires_approval_for_real_action": True,
        "smoke_test": '/usr/local/bin/python3 tools_created_by_lucy/app_open_create_approved.py "open Roblox"'
    })

    save_registry(data)

    print("Created generic App Open tool pair.")
    print("Generated and compiled:")
    print("- tools_created_by_lucy/app_open_dry_run.py")
    print("- tools_created_by_lucy/app_open_create_approved.py")
    print("Updated registry with pair_base, role, and intent_prefixes.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
