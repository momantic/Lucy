#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path


COMMON_APP_DIRS = [
    Path("/Applications"),
    Path("/System/Applications"),
    Path("/System/Applications/Utilities"),
    Path.home() / "Applications",
]


def parse_app_name(text: str) -> str:
    original = text.strip()
    lowered = original.lower()

    prefixes = ["open app ", "launch app ", "open ", "launch ", "start ", "run "]

    for prefix in prefixes:
        if lowered.startswith(prefix):
            app = original[len(prefix):].strip()
            app = re.sub(r"\s+for me\s*$", "", app, flags=re.IGNORECASE).strip()
            app = re.sub(r"\s+please\s*$", "", app, flags=re.IGNORECASE).strip()
            return app

    return original


def normalize_app_text(value: str) -> str:
    value = value.lower().strip()
    if value.endswith(".app"):
        value = value[:-4]
    value = value.replace(".", " ")
    value = value.replace("-", " ")
    value = value.replace("_", " ")
    return " ".join(value.split())


def find_app(app_name: str) -> str | None:
    candidates = []
    cleaned = app_name.strip()
    if not cleaned:
        return None

    if cleaned.lower().endswith(".app"):
        candidates.append(cleaned)
    else:
        candidates.append(cleaned + ".app")

    title = cleaned.title()
    if not title.lower().endswith(".app"):
        candidates.append(title + ".app")

    # 1. Exact path/name checks.
    for app_dir in COMMON_APP_DIRS:
        for candidate in candidates:
            path = app_dir / candidate
            if path.exists():
                return str(path)

    wanted_names = {normalize_app_text(c) for c in candidates}
    wanted_raw = normalize_app_text(cleaned)

    # 2. Fuzzy scan in common app folders.
    # This catches names like zoom.us.app, Zoom Workplace.app, Google Chrome.app, etc.
    for app_dir in COMMON_APP_DIRS:
        if not app_dir.exists():
            continue

        for path in app_dir.glob("*.app"):
            normalized = normalize_app_text(path.name)

            if normalized in wanted_names:
                return str(path)

            if wanted_raw and wanted_raw in normalized:
                return str(path)

            if normalized and normalized in wanted_raw:
                return str(path)

    # 3. Spotlight fallback.
    try:
        import subprocess
        proc = subprocess.run(
            ["/usr/bin/mdfind", f'kMDItemContentType == "com.apple.application-bundle" && kMDItemFSName == "*{cleaned}*"'],
            text=True,
            capture_output=True,
            timeout=5,
        )
        for line in proc.stdout.splitlines():
            line = line.strip()
            if line.endswith(".app"):
                return line
    except Exception:
        pass

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
