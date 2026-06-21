#!/usr/bin/env /usr/local/bin/python3
from __future__ import annotations

import json
import subprocess
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
GENERATOR = PROJECT_ROOT / "tools" / "lucy_tool_pair_generator.py"
REGISTRY = PROJECT_ROOT / "tools_created_by_lucy" / "tool_registry.json"

INTENT_PREFIXES = {
    "mail_draft": [
        "write an email ",
        "write email ",
        "draft an email ",
        "draft email ",
        "create an email ",
        "create email ",
    ],
    "notes": [
        "create a note ",
        "create note ",
        "make a note ",
        "make note ",
        "add a note ",
        "add note ",
    ],
    "reminders": [
        "remind me ",
        "remind me to ",
        "reminder ",
        "set a reminder ",
        "set reminder ",
    ],
    "calendar": [
        "schedule ",
        "schedule a meeting ",
        "schedule meeting ",
        "create calendar event ",
        "add calendar event ",
        "add event ",
        "set up meeting ",
    ],
}


def run(cmd: list[str], timeout: int = 60) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd,
        cwd=str(PROJECT_ROOT),
        text=True,
        capture_output=True,
        timeout=timeout,
    )


def patch_registry() -> None:
    data = json.loads(REGISTRY.read_text())

    for tool in data.get("tools", []):
        name = tool.get("name", "")
        base = None
        role = None

        if name.endswith("_dry_run"):
            base = name.removesuffix("_dry_run")
            role = "dry_run"
        elif name.endswith("_create_approved"):
            base = name.removesuffix("_create_approved")
            role = "create_approved"

        if base in INTENT_PREFIXES:
            tool["pair_base"] = base
            tool["role"] = role
            tool["intent_prefixes"] = tool.get("intent_prefixes") or INTENT_PREFIXES[base]

    REGISTRY.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def patch_generator() -> None:
    text = GENERATOR.read_text()

    if "DEFAULT_INTENT_PREFIXES = {" not in text:
        anchor = 'TEMPLATE_DIR = PROJECT_ROOT / "tools" / "generated_tool_templates"\n'
        block = '''
DEFAULT_INTENT_PREFIXES = {
    "mail_draft": ["write an email ", "write email ", "draft an email ", "draft email ", "create an email ", "create email "],
    "notes": ["create a note ", "create note ", "make a note ", "make note ", "add a note ", "add note "],
    "reminders": ["remind me ", "remind me to ", "reminder ", "set a reminder ", "set reminder "],
    "calendar": ["schedule ", "schedule a meeting ", "schedule meeting ", "create calendar event ", "add calendar event ", "add event ", "set up meeting "],
}


def intent_prefixes_for(tool_type: str, existing_registry: dict) -> list[str]:
    for tool in existing_registry.get("tools", []):
        if tool.get("pair_base") == tool_type and tool.get("intent_prefixes"):
            return tool["intent_prefixes"]
    return DEFAULT_INTENT_PREFIXES.get(tool_type, [])


'''
        if anchor not in text:
            raise RuntimeError("Could not find TEMPLATE_DIR anchor in lucy_tool_pair_generator.py")
        text = text.replace(anchor, anchor + block, 1)

    old_dry = '''    add_or_replace_tool(data, {
        "name": f"{tool_type}_dry_run",
        "path": f"tools_created_by_lucy/{tool_type}_dry_run.py",
        "status": "sandbox",
        "dry_run": True,
        "purpose": f"Template-backed dry-run tool for {tool_type}.",
        "requires_approval_for_real_action": True,
        "smoke_test": f"/usr/local/bin/python3 tools_created_by_lucy/{tool_type}_dry_run.py test"
    })
'''

    new_dry = '''    prefixes = intent_prefixes_for(tool_type, data)

    add_or_replace_tool(data, {
        "name": f"{tool_type}_dry_run",
        "path": f"tools_created_by_lucy/{tool_type}_dry_run.py",
        "status": "sandbox",
        "dry_run": True,
        "pair_base": tool_type,
        "role": "dry_run",
        "intent_prefixes": prefixes,
        "purpose": f"Template-backed dry-run tool for {tool_type}.",
        "requires_approval_for_real_action": True,
        "smoke_test": f"/usr/local/bin/python3 tools_created_by_lucy/{tool_type}_dry_run.py test"
    })
'''

    old_approved = '''    add_or_replace_tool(data, {
        "name": f"{tool_type}_create_approved",
        "path": f"tools_created_by_lucy/{tool_type}_create_approved.py",
        "status": "sandbox",
        "dry_run": False,
        "purpose": f"Template-backed approved action tool for {tool_type}.",
        "requires_approval_for_real_action": True,
        "smoke_test": f"/usr/local/bin/python3 tools_created_by_lucy/{tool_type}_create_approved.py test"
    })
'''

    new_approved = '''    add_or_replace_tool(data, {
        "name": f"{tool_type}_create_approved",
        "path": f"tools_created_by_lucy/{tool_type}_create_approved.py",
        "status": "sandbox",
        "dry_run": False,
        "pair_base": tool_type,
        "role": "create_approved",
        "intent_prefixes": prefixes,
        "purpose": f"Template-backed approved action tool for {tool_type}.",
        "requires_approval_for_real_action": True,
        "smoke_test": f"/usr/local/bin/python3 tools_created_by_lucy/{tool_type}_create_approved.py test"
    })
'''

    if old_dry in text:
        text = text.replace(old_dry, new_dry, 1)

    if old_approved in text:
        text = text.replace(old_approved, new_approved, 1)

    GENERATOR.write_text(text)


def verify_metadata() -> None:
    data = json.loads(REGISTRY.read_text())
    missing = []

    for base in ["mail_draft", "notes", "reminders", "calendar"]:
        entries = [t for t in data.get("tools", []) if t.get("pair_base") == base]
        roles = {t.get("role") for t in entries}

        if len(entries) != 2:
            missing.append(f"{base}: expected 2 registry entries, got {len(entries)}")
        if roles != {"dry_run", "create_approved"}:
            missing.append(f"{base}: bad roles {roles}")
        if not all(t.get("intent_prefixes") for t in entries):
            missing.append(f"{base}: missing intent_prefixes")

    if missing:
        raise RuntimeError("Metadata verification failed:\n" + "\n".join(missing))


def main() -> int:
    patch_registry()
    patch_generator()

    proc = run(["/usr/local/bin/python3", "-m", "py_compile", str(GENERATOR)], timeout=30)
    if proc.returncode != 0:
        print(proc.stderr or proc.stdout)
        return 1

    for tool_type in ["mail_draft", "notes", "reminders", "calendar"]:
        proc = run(["/usr/local/bin/python3", str(GENERATOR), tool_type], timeout=60)
        if proc.returncode != 0:
            print(f"Regeneration failed for {tool_type}")
            print(proc.stdout)
            print(proc.stderr)
            return 1

    verify_metadata()

    print("Updated tool-pair generator registry metadata support successfully.")
    print("Generated entries now include pair_base, role, and intent_prefixes.")
    print("Regenerated and verified: mail_draft, notes, reminders, calendar.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
