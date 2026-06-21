#!/usr/bin/env /usr/local/bin/python3
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DYNAMIC_DIR = PROJECT_ROOT / "tools_created_by_lucy" / "dynamic"
CANDIDATE_DIR = DYNAMIC_DIR / "candidate_tools"
REGISTRY_PATH = PROJECT_ROOT / "tools_created_by_lucy" / "tool_registry.json"
SANDBOX = PROJECT_ROOT / "tools" / "lucy_tool_sandbox.py"
MODEL = os.environ.get("LUCY_MLX_MODEL", "mlx-community/Qwen2.5-Coder-3B-Instruct-4bit")

BANNED = [
    "subprocess", "os.system", "os.popen", "shutil.rmtree",
    "keyring", "keychain", "eval(", "exec(", "__import__", "importlib",
    "open('/", 'open("/', "Path('/", 'Path("/',
    ".unlink(", ".rmdir(", ".rename(", ".replace(",
    "chmod", "chown", "rm -rf",
]


def slug(goal: str) -> str:
    g = goal.lower()
    if "title" in g and ("webpage" in g or "url" in g or "page" in g):
        return "extract_page_title"
    if "link" in g and ("webpage" in g or "url" in g or "page" in g):
        return "extract_links"
    if "search" in g:
        return "public_web_search"
    words = re.findall(r"[a-z0-9]+", g)
    stop = {"create", "make", "build", "write", "tool", "that", "the", "a", "an", "to", "from", "for", "of", "and"}
    useful = [w for w in words if w not in stop][:5]
    return "_".join(useful) or "dynamic_tool"


def extract_code(s: str) -> str:
    m = re.search(r"```(?:python)?\s*(.*?)```", s, re.S | re.I)
    return (m.group(1) if m else s).strip() + "\n"


def validate(code: str) -> tuple[bool, str]:
    low = code.lower()
    for b in BANNED:
        if b.lower() in low:
            return False, f"banned snippet: {b}"
    if "def main" not in code:
        return False, "missing def main"
    if "json.dumps" not in code and "json.dump" not in code:
        return False, "must print JSON"
    return True, "ok"


def call_mlx(prompt: str) -> tuple[bool, str]:
    cmds = [
        ["/usr/local/bin/python3", "-m", "mlx_lm.generate", "--model", MODEL, "--prompt", prompt, "--max-tokens", "1400"],
        ["mlx_lm.generate", "--model", MODEL, "--prompt", prompt, "--max-tokens", "1400"],
    ]
    last = ""
    for cmd in cmds:
        try:
            p = subprocess.run(cmd, cwd=str(PROJECT_ROOT), text=True, capture_output=True, timeout=180)
        except Exception as e:
            last = str(e)
            continue
        if p.returncode == 0 and p.stdout.strip():
            return True, p.stdout.strip()
        last = (p.stderr or p.stdout or "").strip()
    return False, last or "mlx failed"


def prompt_for(goal: str, name: str, repair: str | None = None) -> str:
    base = f"""
You are writing a safe Python 3 command-line tool for Lucy.

Request:
{goal}

Tool name:
{name}

Rules:
- Return only Python code.
- Standard library only.
- Accept input from sys.argv[1:].
- Print exactly one JSON object.
- JSON must include ok and tool.
- The "tool" field must be the literal tool name, not the result.
- Put the result in a separate descriptive field, such as "title", "links", "summary", "items", or "result".
- Example: {{"ok": true, "tool": "extract_page_title", "title": "Example Domain"}}
- Include def main and if __name__ == "__main__".
- Use urllib.request only for read-only public web requests.
- Do not use subprocess, shell, deletion, chmod, chown, keychain, eval, exec, dynamic import, or absolute file access.
- On error, print JSON with ok false and error.
"""
    if repair:
        base += "\nPrevious attempt failed. Fix this error/output:\n" + repair + "\n"
    return base


def py_compile(path: Path) -> tuple[bool, str]:
    p = subprocess.run(["/usr/local/bin/python3", "-m", "py_compile", str(path)], cwd=str(PROJECT_ROOT), text=True, capture_output=True, timeout=30)
    return p.returncode == 0, (p.stderr or p.stdout).strip()


def sandbox(path: Path, arg: str) -> tuple[bool, dict]:
    p = subprocess.run(["/usr/local/bin/python3", str(SANDBOX), str(path), arg], cwd=str(PROJECT_ROOT), text=True, capture_output=True, timeout=45)
    payload = {"exit_code": p.returncode, "stdout": p.stdout.strip(), "stderr": p.stderr.strip()}
    if p.returncode != 0:
        return False, payload
    try:
        outer = json.loads(p.stdout)
        payload["sandbox_json"] = outer
        return bool(outer.get("ok")), payload
    except Exception:
        return False, payload


def load_registry() -> dict:
    if not REGISTRY_PATH.exists():
        return {"tools": []}
    return json.loads(REGISTRY_PATH.read_text())


def save_registry(data: dict) -> None:
    REGISTRY_PATH.parent.mkdir(parents=True, exist_ok=True)
    REGISTRY_PATH.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def register(name: str, path: Path) -> None:
    data = load_registry()
    tools = data.setdefault("tools", [])
    rel = str(path.relative_to(PROJECT_ROOT))
    entry = {
        "name": name,
        "path": rel,
        "status": "react_generated_sandbox",
        "dry_run": True,
        "pair_base": name,
        "role": "dry_run",
        "intent_prefixes": [f"use {name} ", f"{name} "],
        "purpose": f"Lucy ReAct-generated dynamic tool: {name}",
        "requires_approval_for_real_action": False,
        "smoke_test": f"/usr/local/bin/python3 {rel} <input>"
    }
    for i, t in enumerate(tools):
        if t.get("name") == name:
            tools[i] = entry
            save_registry(data)
            return
    tools.append(entry)
    save_registry(data)


def main() -> int:
    if len(sys.argv) < 2:
        print(json.dumps({"ok": False, "error": "usage: lucy_react_toolmaker.py goal smoke_arg"}))
        return 2

    goal = sys.argv[1]
    smoke = sys.argv[2] if len(sys.argv) > 2 else "https://example.com"
    name = slug(goal)

    CANDIDATE_DIR.mkdir(parents=True, exist_ok=True)
    DYNAMIC_DIR.mkdir(parents=True, exist_ok=True)

    candidate = CANDIDATE_DIR / f"{name}.py"
    final = DYNAMIC_DIR / f"{name}.py"
    attempts = []
    repair_text = None

    for attempt in range(1, 3):
        ok, raw = call_mlx(prompt_for(goal, name, repair_text))
        if not ok:
            print(json.dumps({"ok": False, "mode": "mlx_failed", "tool_name": name, "error": raw}, indent=2))
            return 1

        code = extract_code(raw)
        good, msg = validate(code)
        if not good:
            attempts.append({"attempt": attempt, "stage": "validate", "ok": False, "error": msg})
            repair_text = msg
            continue

        candidate.write_text(code)
        candidate.chmod(0o755)

        good, msg = py_compile(candidate)
        if not good:
            attempts.append({"attempt": attempt, "stage": "compile", "ok": False, "error": msg})
            repair_text = msg
            continue

        good, payload = sandbox(candidate, smoke)
        attempts.append({"attempt": attempt, "stage": "sandbox", "ok": good, "payload": payload})
        if good:
            final.write_text(code)
            final.chmod(0o755)
            register(name, final)
            print(json.dumps({
                "ok": True,
                "mode": "react_tool_generated",
                "tool_name": name,
                "path": str(final.relative_to(PROJECT_ROOT)),
                "registered": True,
                "try": f"/tool {name} {smoke}",
                "attempts": attempts
            }, indent=2, ensure_ascii=False))
            return 0

        repair_text = json.dumps(payload, ensure_ascii=False)

    print(json.dumps({
        "ok": False,
        "mode": "react_tool_generation_failed",
        "tool_name": name,
        "attempts": attempts
    }, indent=2, ensure_ascii=False))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
