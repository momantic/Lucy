#!/usr/bin/env /usr/local/bin/python3
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DYNAMIC_DIR = PROJECT_ROOT / "tools_created_by_lucy" / "dynamic"

BANNED_SNIPPETS = [
    "subprocess",
    "os.system",
    "os.popen",
    "shutil.rmtree",
    "socket",
    "keyring",
    "keychain",
    "eval(",
    "exec(",
    "__import__",
    "importlib",
    "open('/",
    'open("/',
    "Path('/",
    'Path("/',
    ".unlink(",
    ".rmdir(",
    ".rename(",
    ".replace(",
    "chmod",
    "chown",
    "rm -rf",
]


def validate_code(path: Path) -> tuple[bool, str]:
    try:
        resolved = path.resolve()
        dynamic_root = DYNAMIC_DIR.resolve()
        if dynamic_root not in resolved.parents and resolved != dynamic_root:
            return False, f"Refusing to run outside dynamic sandbox: {resolved}"

        code = path.read_text()
    except Exception as e:
        return False, str(e)

    lowered = code.lower()
    for banned in BANNED_SNIPPETS:
        if banned.lower() in lowered:
            return False, f"Rejected dangerous snippet: {banned}"

    return True, "ok"


def run_tool(path: Path, args: list[str]) -> int:
    if not path.is_absolute():
        path = (PROJECT_ROOT / path).resolve()

    ok, msg = validate_code(path)
    if not ok:
        print(json.dumps({
            "ok": False,
            "stage": "validation",
            "error": msg
        }, indent=2))
        return 1

    env = {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "PYTHONNOUSERSITE": "1",
        "LUCY_DYNAMIC_SANDBOX": str(DYNAMIC_DIR),
    }

    proc = subprocess.run(
        ["/usr/bin//usr/local/bin/python3", str(path), *args],
        cwd=str(DYNAMIC_DIR),
        text=True,
        capture_output=True,
        timeout=10,
        env=env,
    )

    print(json.dumps({
        "ok": proc.returncode == 0,
        "exit_code": proc.returncode,
        "stdout": proc.stdout.strip(),
        "stderr": proc.stderr.strip()
    }, indent=2, ensure_ascii=False))

    return 0 if proc.returncode == 0 else 1


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: lucy_tool_sandbox.py <tool_path> [args...]", file=sys.stderr)
        return 2

    return run_tool(Path(sys.argv[1]), sys.argv[2:])


if __name__ == "__main__":
    raise SystemExit(main())
