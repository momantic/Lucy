#!/usr/bin/env python3

from __future__ import annotations

import argparse
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


def run(cmd: list[str]) -> tuple[int, str]:
    proc = subprocess.run(
        cmd,
        cwd=str(PROJECT_ROOT),
        text=True,
        capture_output=True,
        timeout=180,
    )
    return proc.returncode, "\n".join(
        part for part in [proc.stdout.strip(), proc.stderr.strip()] if part
    )


def infer_spec(goal: str) -> dict:
    lowered = goal.lower()

    if any(w in lowered for w in ["download", "install", "discord", "remove app", "uninstall", "delete app"]):
        return {
            "capability": "app_download_remove",
            "tool_names": ["open_url", "download_file", "download_known_app", "remove_app_to_trash"],
            "purpose": "Download known Mac apps safely and move installed apps to Trash.",
            "safety": [
                "Only HTTPS downloads.",
                "Download to ~/Downloads.",
                "Do not install or run downloaded apps without explicit user approval.",
                "Move apps to Trash instead of permanently deleting them."
            ],
            "test_goal": "Download Discord for me."
        }

    if any(w in lowered for w in ["schedule", "calendar", "meeting", "zoom meeting", "add to calendar"]):
        return {
            "capability": "calendar_event",
            "tool_names": ["create_calendar_event"],
            "purpose": "Create local Apple Calendar events from a title, start time, end time, location, and notes.",
            "safety": [
                "Do not send invitations.",
                "Do not claim to create a real Zoom link unless one is provided.",
                "If duration is missing, default to one hour."
            ],
            "test_goal": "Schedule a Zoom meeting at 3:30 PM on June 11, 2026."
        }

    if any(w in lowered for w in ["open website", "open url", "go to", "website", "wikipedia", "youtube"]):
        return {
            "capability": "open_url",
            "tool_names": ["open_url"],
            "purpose": "Open safe http/https URLs in the user's browser.",
            "safety": [
                "Only open http/https URLs.",
                "Do not submit forms or click destructive buttons."
            ],
            "test_goal": "Open wikipedia.org."
        }

    if any(w in lowered for w in ["copy", "clipboard", "paste"]):
        return {
            "capability": "clipboard",
            "tool_names": ["copy_to_clipboard"],
            "purpose": "Copy text to the clipboard safely.",
            "safety": [
                "Only copy text.",
                "Do not paste into other apps unless a separate approved UI tool is used."
            ],
            "test_goal": "Copy hello to my clipboard."
        }

    return {
        "capability": "unknown",
        "tool_names": [],
        "purpose": "Unknown capability.",
        "safety": [
            "Do not implement unknown high-risk capabilities automatically."
        ],
        "test_goal": goal
    }


def save_spec(goal: str, spec: dict) -> Path:
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    safe_capability = re.sub(r"[^a-zA-Z0-9_\-]", "_", spec.get("capability", "unknown"))
    path = SPEC_DIR / f"{stamp}_{safe_capability}.json"
    path.write_text(json.dumps({
        "goal": goal,
        "spec": spec,
    }, indent=2))
    return path


def insert_before_function(text: str, function_marker: str, code: str) -> str:
    marker = f"\ndef {function_marker}"
    if marker not in text:
        raise RuntimeError(f"Could not find insertion marker {marker}")
    return text.replace(marker, "\n" + code + marker, 1)


def ensure_tool_registration(text: str, registration: str) -> str:
    if registration in text:
        return text
    if "TOOLS = {" not in text:
        raise RuntimeError("Could not find TOOLS block.")
    return text.replace("TOOLS = {", "TOOLS = {\n    " + registration, 1)


def ensure_prompt_before_find_app(text: str, prompt_block: str) -> str:
    if prompt_block.strip() in text:
        return text

    target = '''1. find_app
Args: {"name": "Messages"}
Purpose: Check whether a Mac app exists.'''

    if target not in text:
        raise RuntimeError("Could not find prompt insertion point before find_app.")

    return text.replace(target, prompt_block + target, 1)


def ensure_rule(text: str, rule: str) -> str:
    if rule.strip() in text:
        return text

    marker = "- Keep responses short and action-oriented."
    if marker in text:
        return text.replace(marker, marker + "\n" + rule, 1)

    marker2 = "Important safety rules:"
    if marker2 in text:
        return text.replace(marker2, marker2 + "\n" + rule, 1)

    raise RuntimeError("Could not find rule insertion point.")


APP_DOWNLOAD_CODE = r'''
def tool_open_url(args: dict) -> dict:
    url = str(args.get("url", "")).strip()

    if not url:
        return {"ok": False, "error": "Missing url."}

    if not (url.startswith("https://") or url.startswith("http://")):
        return {"ok": False, "error": "Only http/https URLs are allowed."}

    code, out = run(["open", url], timeout=20)

    return {
        "ok": code == 0,
        "url": url,
        "output": out or "Opened URL."
    }


def tool_download_file(args: dict) -> dict:
    url = str(args.get("url", "")).strip()
    filename = str(args.get("filename", "")).strip()

    if not url:
        return {"ok": False, "error": "Missing url."}

    if not url.startswith("https://"):
        return {"ok": False, "error": "Only https downloads are allowed."}

    if not filename:
        filename = url.split("/")[-1] or "downloaded_file"

    downloads = Path.home() / "Downloads"
    downloads.mkdir(exist_ok=True)
    dest = downloads / filename

    code, out = run([
        "curl",
        "-L",
        "--fail",
        "--show-error",
        "--output",
        str(dest),
        url,
    ], timeout=600)

    if code != 0:
        return {
            "ok": False,
            "url": url,
            "filename": filename,
            "error": out,
        }

    return {
        "ok": True,
        "url": url,
        "path": str(dest),
        "safety": "Downloaded file only. Did not install or run it."
    }


def tool_download_known_app(args: dict) -> dict:
    app_name = str(args.get("app_name", "")).strip().lower()

    known_apps = {
        "discord": {
            "display": "Discord",
            "url": "https://discord.com/api/download?platform=osx",
            "filename": "Discord.dmg",
        }
    }

    if app_name not in known_apps:
        return {
            "ok": False,
            "error": f"Unknown app: {app_name}",
            "supported_apps": sorted(known_apps.keys()),
            "hint": "Use open_url to open the official website, or extend known_apps after verifying the official download URL."
        }

    item = known_apps[app_name]
    return tool_download_file({
        "url": item["url"],
        "filename": item["filename"],
    })


def tool_remove_app_to_trash(args: dict) -> dict:
    app_name = str(args.get("app_name", "")).strip()

    if not app_name:
        return {"ok": False, "error": "Missing app_name."}

    app_bundle = app_name if app_name.endswith(".app") else app_name + ".app"

    candidates = [
        Path("/Applications") / app_bundle,
        Path.home() / "Applications" / app_bundle,
    ]

    existing = [p for p in candidates if p.exists()]

    if not existing:
        return {
            "ok": False,
            "error": f"Could not find {app_bundle} in /Applications or ~/Applications.",
            "searched": [str(p) for p in candidates],
        }

    target = existing[0]

    script = (
        f'tell application "Finder"\n'
        f'    move POSIX file "{str(target)}" to trash\n'
        f'end tell\n'
    )

    code, out = run(["osascript", "-e", script], timeout=30)

    if code != 0:
        return {
            "ok": False,
            "error": out,
            "target": str(target),
            "hint": "Finder/Automation permission may be required."
        }

    return {
        "ok": True,
        "removed": str(target),
        "safety": "Moved app to Trash. Did not permanently delete it."
    }

'''


CALENDAR_CODE = r'''
def tool_create_calendar_event(args: dict) -> dict:
    title = str(args.get("title", "Untitled event")).strip() or "Untitled event"
    start = str(args.get("start", "")).strip()
    end = str(args.get("end", "")).strip()
    location = str(args.get("location", "")).strip()
    notes = str(args.get("notes", "")).strip()

    if not start:
        return {
            "ok": False,
            "error": "Missing start datetime. Use a natural date like: June 11, 2026 3:30 PM"
        }

    if not end:
        return {
            "ok": False,
            "error": "Missing end datetime. If duration is not specified, default to one hour."
        }

    def esc(s: str) -> str:
        return s.replace("\\", "\\\\").replace('"', '\\"')

    title_e = esc(title)
    start_e = esc(start)
    end_e = esc(end)
    location_e = esc(location)
    notes_e = esc(notes)

    apple_script = (
        f'set eventTitle to "{title_e}"\n'
        f'set startText to "{start_e}"\n'
        f'set endText to "{end_e}"\n'
        f'set eventLocation to "{location_e}"\n'
        f'set eventNotes to "{notes_e}"\n'
        'set startDate to date startText\n'
        'set endDate to date endText\n'
        'tell application "Calendar"\n'
        '    activate\n'
        '    set targetCalendar to missing value\n'
        '    try\n'
        '        set targetCalendar to calendar "Home"\n'
        '    end try\n'
        '    if targetCalendar is missing value then\n'
        '        set targetCalendar to first calendar\n'
        '    end if\n'
        '    tell targetCalendar\n'
        '        make new event with properties {summary:eventTitle, start date:startDate, end date:endDate, location:eventLocation, description:eventNotes}\n'
        '    end tell\n'
        'end tell\n'
    )

    code, out = run(["osascript", "-e", apple_script], timeout=30)

    if code != 0:
        return {
            "ok": False,
            "error": out,
            "hint": "macOS may require Calendar permission for Lucy or osascript. This creates a local Calendar event only."
        }

    return {
        "ok": True,
        "title": title,
        "start": start,
        "end": end,
        "location": location,
        "notes": notes,
        "safety": "Created a local Apple Calendar event. No invitations were sent and no real Zoom link was created."
    }

'''


def build_capability(spec: dict) -> dict:
    capability = spec.get("capability")
    text = AGENT_LOOP.read_text()
    before = text

    if capability == "app_download_remove":
        if "def tool_download_known_app" not in text:
            text = insert_before_function(text, "tool_find_app", APP_DOWNLOAD_CODE)

        for reg in [
            '"open_url": tool_open_url,',
            '"download_file": tool_download_file,',
            '"download_known_app": tool_download_known_app,',
            '"remove_app_to_trash": tool_remove_app_to_trash,',
        ]:
            text = ensure_tool_registration(text, reg)

        text = ensure_prompt_before_find_app(text, '''0.6 open_url
Args: {"url": "https://example.com"}
Purpose: Open a safe http/https URL in the browser.

0.7 download_file
Args: {"url": "https://example.com/file.dmg", "filename": "file.dmg"}
Purpose: Download an HTTPS file to ~/Downloads. Does not install or run it.

0.8 download_known_app
Args: {"app_name": "Discord"}
Purpose: Download a known app from a verified official source. Currently supports Discord. Does not install or run it.

0.9 remove_app_to_trash
Args: {"app_name": "Discord"}
Purpose: Move an installed app from /Applications or ~/Applications to Trash. Does not permanently delete it.

''')

        text = ensure_rule(text, '''- For app download requests, prefer download_known_app if the app is supported. Do not install or run downloaded apps without explicit user approval.
- For removing/uninstalling apps, use remove_app_to_trash. Do not permanently delete apps.''')

    elif capability == "calendar_event":
        if "def tool_create_calendar_event" not in text:
            text = insert_before_function(text, "tool_find_app", CALENDAR_CODE)

        text = ensure_tool_registration(text, '"create_calendar_event": tool_create_calendar_event,')

        text = ensure_prompt_before_find_app(text, '''0.5 create_calendar_event
Args: {"title": "Zoom meeting", "start": "June 11, 2026 3:30 PM", "end": "June 11, 2026 4:30 PM", "location": "Zoom", "notes": "Zoom link not provided"}
Purpose: Create a local Apple Calendar event. Does not send invitations. Does not create a real Zoom meeting link.

''')

        text = ensure_rule(text, '''- For scheduling/calendar requests, use create_calendar_event when the user provides a date and time.
- If duration is not specified, default to one hour.
- If the user says "Zoom meeting" but provides no Zoom link, create a Calendar event with location "Zoom" and notes "Zoom link not provided"; do not claim to create a real Zoom meeting link.''')

    else:
        return {
            "ok": False,
            "changed": False,
            "changed_files": [],
            "error": f"Tool Builder v0.2 does not yet support capability: {capability}",
            "capability": capability,
        }

    changed = text != before

    if changed:
        backup = AGENT_LOOP.with_suffix(".py.bak-tool-builder")
        backup.write_text(before)
        AGENT_LOOP.write_text(text)

    code, out = run([sys.executable, "-m", "py_compile", str(AGENT_LOOP)])

    return {
        "ok": code == 0,
        "changed": changed,
        "changed_files": ["tools/lucy_agent_loop.py"] if changed else [],
        "compile_output": out,
        "capability": capability,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("goal", nargs="+")
    parser.add_argument("--spec", type=str, default="")
    args = parser.parse_args()

    goal = " ".join(args.goal).strip()

    if args.spec:
        spec_path = Path(args.spec)
        data = json.loads(spec_path.read_text())
        spec = data.get("spec", data)
    else:
        spec = infer_spec(goal)

    spec_path = save_spec(goal, spec)

    print("# Lucy Tool Builder v0.2")
    print(f"Goal: {goal}")
    print(f"Inferred capability: {spec.get('capability')}")
    print(f"Spec saved: {spec_path}")
    print("")

    result = build_capability(spec)

    print(json.dumps(result, indent=2))

    if result.get("ok"):
        print("")
        print("STATUS: PASSED")
        print("Changed files:")
        if result.get("changed_files"):
            for f in result["changed_files"]:
                print(f"- {f}")
        else:
            print("- none")
        return 0

    print("")
    print("STATUS: FAILED")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
