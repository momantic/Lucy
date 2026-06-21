#!/usr/bin/env /usr/local/bin/python3
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
TOOLS_DIR = PROJECT_ROOT / "tools_created_by_lucy"
REGISTRY = TOOLS_DIR / "tool_registry.json"
TEMPLATE_DIR = PROJECT_ROOT / "tools" / "generated_tool_templates"

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




def ensure_registry() -> dict:
    TOOLS_DIR.mkdir(parents=True, exist_ok=True)
    if not REGISTRY.exists():
        REGISTRY.write_text(json.dumps({"tools": []}, indent=2) + "\n")
        return {"tools": []}

    raw = REGISTRY.read_text().strip()
    if not raw:
        return {"tools": []}

    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        decoder = json.JSONDecoder()
        data, _ = decoder.raw_decode(raw)
        REGISTRY.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        return data


def write_registry(data: dict) -> None:
    REGISTRY.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def py_compile(path: Path) -> tuple[bool, str]:
    proc = subprocess.run(
        ["/usr/local/bin/python3", "-m", "py_compile", str(path)],
        cwd=str(PROJECT_ROOT),
        text=True,
        capture_output=True,
        timeout=30,
    )
    return proc.returncode == 0, proc.stderr.strip() or proc.stdout.strip()


def add_or_replace_tool(data: dict, entry: dict) -> None:
    tools = data.setdefault("tools", [])
    by_name = {tool.get("name"): tool for tool in tools}
    by_name[entry["name"]] = entry
    data["tools"] = list(by_name.values())


def pair_base_from_dry_run_name(name: str) -> str:
    return name.removesuffix("_dry_run.py")


def approved_name_for_base(base: str) -> str:
    return f"{base}_create_approved.py"


def import_existing_pairs() -> list[str]:
    """
    Scan tools_created_by_lucy for existing *_dry_run.py + *_create_approved.py pairs
    and copy them into tools/generated_tool_templates/.

    This lets the generator regenerate known-good tools without inventing code.
    """
    TEMPLATE_DIR.mkdir(parents=True, exist_ok=True)
    imported: list[str] = []

    for dry_path in sorted(TOOLS_DIR.glob("*_dry_run.py")):
        base = pair_base_from_dry_run_name(dry_path.name)
        approved_path = TOOLS_DIR / approved_name_for_base(base)

        if not approved_path.exists():
            continue

        ok1, msg1 = py_compile(dry_path)
        ok2, msg2 = py_compile(approved_path)
        if not ok1 or not ok2:
            print(f"Skipping {base}: py_compile failed")
            if msg1:
                print(msg1)
            if msg2:
                print(msg2)
            continue

        target_dry = TEMPLATE_DIR / dry_path.name
        target_approved = TEMPLATE_DIR / approved_path.name
        shutil.copy2(dry_path, target_dry)
        shutil.copy2(approved_path, target_approved)
        imported.append(base)

    return imported


def generate_from_imported_template(tool_type: str) -> list[Path]:
    dry_template = TEMPLATE_DIR / f"{tool_type}_dry_run.py"
    approved_template = TEMPLATE_DIR / f"{tool_type}_create_approved.py"

    if not dry_template.exists() or not approved_template.exists():
        raise SystemExit(
            f"No imported template for {tool_type}. Run: /usr/local/bin/python3 tools/lucy_tool_pair_generator.py --import-existing"
        )

    TOOLS_DIR.mkdir(parents=True, exist_ok=True)
    dry_path = TOOLS_DIR / dry_template.name
    approved_path = TOOLS_DIR / approved_template.name

    shutil.copy2(dry_template, dry_path)
    shutil.copy2(approved_template, approved_path)
    dry_path.chmod(0o755)
    approved_path.chmod(0o755)

    data = ensure_registry()
    prefixes = intent_prefixes_for(tool_type, data)

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
    add_or_replace_tool(data, {
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
    write_registry(data)

    return [dry_path, approved_path, REGISTRY]


def list_supported() -> list[str]:
    TEMPLATE_DIR.mkdir(parents=True, exist_ok=True)
    bases = []
    for dry_path in TEMPLATE_DIR.glob("*_dry_run.py"):
        base = pair_base_from_dry_run_name(dry_path.name)
        if (TEMPLATE_DIR / approved_name_for_base(base)).exists():
            bases.append(base)
    return sorted(set(bases))


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Lucy Apple action tool pairs.")
    parser.add_argument("tool_type", nargs="?", help="Tool type to generate, such as notes, reminders, calendar, mail_draft.")
    parser.add_argument("--import-existing", action="store_true", help="Import existing working tool pairs as templates.")
    parser.add_argument("--list-supported", action="store_true", help="List supported imported template-backed tool types.")
    args = parser.parse_args()

    if args.import_existing:
        imported = import_existing_pairs()
        print("Imported existing tool-pair templates:")
        for base in imported:
            print("-", base)
        print("STATUS: PASSED")
        return 0

    if args.list_supported:
        print("Supported template-backed tool types:")
        for base in list_supported():
            print("-", base)
        return 0

    if not args.tool_type:
        parser.error("tool_type is required unless --import-existing or --list-supported is used")

    changed = generate_from_imported_template(args.tool_type)

    print("Generated/updated files:")
    for path in changed:
        print("-", path.relative_to(PROJECT_ROOT))

    print()
    print("Compiling generated Python tools...")
    ok_all = True
    for path in changed:
        if path.suffix == ".py":
            ok, msg = py_compile(path)
            print(f"- {path.relative_to(PROJECT_ROOT)}: {'OK' if ok else 'FAILED'}")
            if msg:
                print(msg)
            ok_all = ok_all and ok

    if not ok_all:
        print("STATUS: FAILED_PY_COMPILE")
        return 2

    print("STATUS: PASSED")
    print("Tool pair generated successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
