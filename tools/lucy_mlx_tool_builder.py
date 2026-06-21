#!/usr/bin/env /usr/local/bin/python3

from __future__ import annotations

import argparse
import ast
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path


PROJECT_ROOT = Path("/Users/michaelzheng/lucy").resolve()
AGENT_LOOP = PROJECT_ROOT / "tools" / "lucy_agent_loop.py"
SPEC_DIR = PROJECT_ROOT / ".lucy" / "tool_specs"
SPEC_DIR.mkdir(parents=True, exist_ok=True)

def load_dev_model() -> str:
    config_path = PROJECT_ROOT / "data" / "model_provider.json"
    try:
        config = json.loads(config_path.read_text())
        return config.get("dev_model") or config.get("chat_model") or "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit"
    except Exception:
        return "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit"


MODEL = load_dev_model()


DANGEROUS_STRINGS = [
    "sudo ",
    "rm -rf",
    "rm -fr",
    "mkfs",
    "diskutil erase",
    "curl | sh",
    "curl|sh",
    "wget | sh",
    "chmod 777",
    "chown ",
    "launchctl",
    "security ",
    "keychain",
    "osascript -e 'do shell script",
    "do shell script",
    "killall",
    "pkill",
    "shutdown",
    "reboot",
    "dd if=",
    "base64 -d | sh",
]

BANNED_CALL_NAMES = {
    "eval",
    "exec",
    "compile",
    "__import__",
    "input",
}

BANNED_ATTR_CALLS = {
    ("os", "system"),
    ("subprocess", "Popen"),
}


def run(cmd: list[str], timeout: int = 600) -> tuple[int, str]:
    proc = subprocess.run(
        cmd,
        cwd=str(PROJECT_ROOT),
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    out = "\n".join(part for part in [proc.stdout.strip(), proc.stderr.strip()] if part)
    return proc.returncode, out.strip()


def call_mlx(prompt: str) -> str:
    code, out = run([
        sys.executable,
        "-m",
        "mlx_lm",
        "generate",
        "--model",
        MODEL,
        "--prompt",
        prompt,
        "--max-tokens",
        "2200",
        "--verbose",
        "False",
    ], timeout=900)

    if code != 0:
        raise RuntimeError(out)

    return out


def extract_json(text: str) -> dict:
    text = text.strip()

    # Preferred old path: valid JSON.
    try:
        obj = json.loads(text)
        if isinstance(obj, dict):
            return obj
    except Exception:
        pass

    # Try JSON object substring.
    match = re.search(r"\{.*\}", text, flags=re.S)
    if match:
        try:
            obj = json.loads(match.group(0))
            if isinstance(obj, dict):
                return obj
        except Exception:
            pass

    # Robust local-model fallback format:
    # TOOL_NAME: ...
    # DESCRIPTION: ...
    # ARGS_EXAMPLE: {...}
    # PROMPT_DOC:
    # ...
    # TOOL_CODE:
    # def ...
    # END_TOOL_CODE
    name_match = re.search(r"TOOL_NAME:\s*(?P<name>[A-Za-z0-9_]+)", text)
    desc_match = re.search(r"DESCRIPTION:\s*(?P<desc>.*)", text)
    args_match = re.search(r"ARGS_EXAMPLE:\s*(?P<args>\{.*?\})", text, flags=re.S)
    prompt_match = re.search(r"PROMPT_DOC:\s*(?P<prompt>.*?)(?:\nTOOL_CODE:)", text, flags=re.S)
    code_match = re.search(r"TOOL_CODE:\s*(?P<code>.*?)(?:\nEND_TOOL_CODE|\Z)", text, flags=re.S)

    if name_match and code_match:
        args_example = {}
        if args_match:
            try:
                args_example = json.loads(args_match.group("args"))
            except Exception:
                args_example = {}

        return {
            "tool_name": name_match.group("name").strip(),
            "description": desc_match.group("desc").strip() if desc_match else "",
            "args_example": args_example,
            "prompt_doc": prompt_match.group("prompt").strip() if prompt_match else "",
            "code": code_match.group("code").strip(),
        }

    raise RuntimeError("Could not parse MLX tool-builder output as JSON or TOOL_CODE format.\n\nRAW OUTPUT:\n" + text[:2000])


def snake_name(name: str) -> str:
    name = name.strip()
    name = re.sub(r"[^a-zA-Z0-9_]+", "_", name)
    name = re.sub(r"_+", "_", name).strip("_").lower()
    if not name.startswith("tool_"):
        name = "tool_" + name
    return name


def make_prompt(goal: str) -> str:
    return f"""
You are generating ONE safe local Python tool for Lucy.

Lucy tool rules:
- Output ONLY valid JSON.
- Do not use markdown.
- The tool must be a single Python function named tool_<something>(args: dict) -> dict.
- The function must return a dict with ok: true/false.
- Do not include imports.
- You may use these existing names: Path, run, subprocess, json, re.
- Prefer safe local actions.
- Do not send messages/emails.
- Do not spend money.
- Do not use sudo.
- Do not permanently delete files.
- Do not access passwords, Keychain, tokens, or private secrets.
- Do not bypass macOS permissions.
- If the task needs permission/account/login, the tool should return ok:false with a clear hint.
- If the action is destructive, prefer moving to Trash or asking approval.
- Keep code short.

User goal:
{goal}

Return JSON exactly like:
{{
  "tool_name": "tool_example_name",
  "description": "What this tool does",
  "args_example": {{"example_arg": "value"}},
  "prompt_doc": "Tool documentation for Lucy's Available tools list",
  "code": "def tool_example_name(args: dict) -> dict:\\n    return {{\\"ok\\": True}}"
}}
""".strip()


def static_safety_check(tool_name: str, code: str) -> tuple[bool, str]:
    lowered = code.lower()

    for bad in DANGEROUS_STRINGS:
        if bad in lowered:
            return False, f"Rejected dangerous string: {bad}"

    try:
        tree = ast.parse(code)
    except SyntaxError as e:
        return False, f"Syntax error: {e}"

    funcs = [node for node in tree.body if isinstance(node, ast.FunctionDef)]
    if len(funcs) != 1:
        return False, "Code must contain exactly one top-level function."

    func = funcs[0]
    if func.name != tool_name:
        return False, f"Function name {func.name} does not match tool_name {tool_name}."

    if not tool_name.startswith("tool_"):
        return False, "Tool name must start with tool_."

    for node in ast.walk(tree):
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            return False, "Imports are not allowed in generated tool code."

        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name) and node.func.id in BANNED_CALL_NAMES:
                return False, f"Banned call: {node.func.id}"

            if isinstance(node.func, ast.Attribute):
                base = node.func.value
                if isinstance(base, ast.Name):
                    pair = (base.id, node.func.attr)
                    if pair in BANNED_ATTR_CALLS:
                        return False, f"Banned call: {base.id}.{node.func.attr}"

    return True, "Static safety check passed."


def insert_tool(tool_name: str, code: str, prompt_doc: str) -> tuple[bool, str]:
    text = AGENT_LOOP.read_text()
    before = text

    if f"def {tool_name}(" not in text:
        marker = "\ndef tool_find_app"
        if marker not in text:
            raise RuntimeError("Could not find insertion marker def tool_find_app.")
        text = text.replace(marker, "\n" + code.rstrip() + "\n" + marker, 1)

    reg = f'"{tool_name.removeprefix("tool_")}": {tool_name},'
    if reg not in text:
        if "TOOLS = {" not in text:
            raise RuntimeError("Could not find TOOLS block.")
        text = text.replace("TOOLS = {", "TOOLS = {\n    " + reg, 1)

    if prompt_doc not in text:
        target = '''1. find_app
Args: {"name": "Messages"}
Purpose: Check whether a Mac app exists.'''
        if target in text:
            text = text.replace(target, prompt_doc.rstrip() + "\n\n" + target, 1)
        else:
            # Fallback: add near Available tools.
            text = text.replace("Available tools:", "Available tools:\n\n" + prompt_doc.rstrip(), 1)

    changed = text != before

    if changed:
        backup = AGENT_LOOP.with_suffix(".py.bak-mlx-tool-builder")
        backup.write_text(before)
        AGENT_LOOP.write_text(text)

    code_status, compile_out = run([sys.executable, "-m", "py_compile", str(AGENT_LOOP)], timeout=120)

    if code_status != 0:
        AGENT_LOOP.write_text(before)
        return False, "Compile failed; rolled back:\n" + compile_out

    return changed, "Inserted and compiled." if changed else "Tool already existed."


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("goal", nargs="+")
    args = parser.parse_args()

    goal = " ".join(args.goal).strip()
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    print("# Lucy MLX Arbitrary Tool Builder")
    print(f"Goal: {goal}")
    print(f"Model: {MODEL}")
    print("")

    raw = call_mlx(make_prompt(goal))
    spec = extract_json(raw)

    tool_name = snake_name(str(spec.get("tool_name", "")))
    description = str(spec.get("description", "")).strip()
    args_example = spec.get("args_example", {})
    prompt_doc = str(spec.get("prompt_doc", "")).strip()
    code = str(spec.get("code", "")).strip()

    if not prompt_doc:
        prompt_doc = f'''Generated tool: {tool_name.removeprefix("tool_")}
Args: {json.dumps(args_example)}
Purpose: {description}'''

    # Force code function name to match if model gave compatible code name.
    code = re.sub(r"def\s+tool_[a-zA-Z0-9_]+\s*\(", f"def {tool_name}(", code, count=1)

    spec_path = SPEC_DIR / f"{stamp}_{tool_name}.json"
    spec_path.write_text(json.dumps({
        "goal": goal,
        "tool_name": tool_name,
        "description": description,
        "args_example": args_example,
        "prompt_doc": prompt_doc,
        "code": code,
    }, indent=2))

    ok, reason = static_safety_check(tool_name, code)
    print("STATIC SAFETY:")
    print(reason)
    print("")

    if not ok:
        print(f"Spec saved: {spec_path}")
        print("STATUS: FAILED")
        return 1

    changed, insert_reason = insert_tool(tool_name, code, prompt_doc)

    print("INSERT:")
    print(insert_reason)
    print(f"Spec saved: {spec_path}")
    print("")

    if changed:
        print("STATUS: PASSED")
        print("Changed files:")
        print("- tools/lucy_agent_loop.py")
    else:
        print("STATUS: PASSED")
        print("Changed files:")
        print("- none")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
