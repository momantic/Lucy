#!/usr/bin/env /usr/local/bin/python3
from __future__ import annotations

import json
import subprocess
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
TOOLS_DIR = PROJECT_ROOT / "tools_created_by_lucy"
REGISTRY = TOOLS_DIR / "tool_registry.json"

INTENT_PREFIXES = [
    "open website ",
    "open safari to ",
    "open url ",
    "open link ",
    "go to website ",
]

DRY_RUN = '''#!/usr/bin/env /usr/local/bin/python3
from __future__ import annotations

import json
import re
import sys
from urllib.parse import urlparse


def normalize_url(value: str) -> str:
    value = value.strip()
    if not value:
        return ""

    if not re.match(r"^https?://", value, flags=re.IGNORECASE):
        value = "https://" + value

    return value


def parse_request(text: str) -> dict:
    original = text.strip()

    cleaned = re.sub(
        r"^\\s*(open website|open safari to|open url|open link|go to website)\\s+",
        "",
        original,
        flags=re.IGNORECASE,
    ).strip()

    url = normalize_url(cleaned)
    parsed = urlparse(url)

    valid = bool(parsed.scheme in {"http", "https"} and parsed.netloc)

    return {
        "dry_run": True,
        "tool": "safari_open_dry_run",
        "original_request": original,
        "parsed": {
            "url": url,
            "valid_url": valid
        },
        "would_open_safari": False,
        "safety_note": "Dry run only. Safari was not opened."
    }


def main() -> int:
    if len(sys.argv) < 2:
        print('Usage: safari_open_dry_run.py "open website https://example.com"', file=sys.stderr)
        return 2

    result = parse_request(" ".join(sys.argv[1:]))
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

from safari_open_dry_run import parse_request


def main() -> int:
    if len(sys.argv) < 2:
        print('Usage: safari_open_create_approved.py "open website https://example.com"', file=sys.stderr)
        return 2

    request = " ".join(sys.argv[1:])
    parsed = parse_request(request)
    info = parsed["parsed"]

    if not info.get("valid_url"):
        print(json.dumps({
            "created": False,
            "tool": "safari_open_create_approved",
            "error": "Invalid URL.",
            "parsed": info,
            "safety_note": "Safari was not opened because URL validation failed."
        }, indent=2, ensure_ascii=False))
        return 1

    url = info["url"]

    proc = subprocess.run(
        ["/usr/bin/open", "-a", "Safari", url],
        text=True,
        capture_output=True,
        timeout=15,
    )

    if proc.returncode != 0:
        print(json.dumps({
            "created": False,
            "tool": "safari_open_create_approved",
            "url": url,
            "error": proc.stderr.strip() or proc.stdout.strip() or "open command failed",
            "safety_note": "Safari may not have opened."
        }, indent=2, ensure_ascii=False))
        return 1

    print(json.dumps({
        "created": True,
        "tool": "safari_open_create_approved",
        "url": url,
        "safety_note": "Opened Safari only after explicit approval."
    }, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'''


def load_registry() -> dict:
    TOOLS_DIR.mkdir(parents=True, exist_ok=True)
    if not REGISTRY.exists():
        return {"tools": []}
    return json.loads(REGISTRY.read_text())


def save_registry(data: dict) -> None:
    REGISTRY.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def add_or_replace(data: dict, entry: dict) -> None:
    tools = data.setdefault("tools", [])
    by_name = {t.get("name"): t for t in tools}
    by_name[entry["name"]] = entry
    data["tools"] = list(by_name.values())


def main() -> int:
    TOOLS_DIR.mkdir(parents=True, exist_ok=True)

    dry_path = TOOLS_DIR / "safari_open_dry_run.py"
    approved_path = TOOLS_DIR / "safari_open_create_approved.py"

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
        "name": "safari_open_dry_run",
        "path": "tools_created_by_lucy/safari_open_dry_run.py",
        "status": "sandbox",
        "dry_run": True,
        "pair_base": "safari_open",
        "role": "dry_run",
        "intent_prefixes": INTENT_PREFIXES,
        "purpose": "Parse Safari open-url requests and preview the URL without opening Safari.",
        "requires_approval_for_real_action": True,
        "smoke_test": '/usr/local/bin/python3 tools_created_by_lucy/safari_open_dry_run.py "open website https://example.com"'
    })

    add_or_replace(data, {
        "name": "safari_open_create_approved",
        "path": "tools_created_by_lucy/safari_open_create_approved.py",
        "status": "sandbox",
        "dry_run": False,
        "pair_base": "safari_open",
        "role": "create_approved",
        "intent_prefixes": INTENT_PREFIXES,
        "purpose": "Open a URL in Safari after Lucy has shown a preview and the user has explicitly approved.",
        "requires_approval_for_real_action": True,
        "smoke_test": '/usr/local/bin/python3 tools_created_by_lucy/safari_open_create_approved.py "open website https://example.com"'
    })

    save_registry(data)

    print("Created Safari open Apple action tool pair.")
    print("Generated and compiled:")
    print("- tools_created_by_lucy/safari_open_dry_run.py")
    print("- tools_created_by_lucy/safari_open_create_approved.py")
    print("Updated registry with pair_base, role, and intent_prefixes.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
