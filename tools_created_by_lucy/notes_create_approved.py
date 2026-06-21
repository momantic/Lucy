#!/usr/bin/env python3
"""
Lucy-created tool: notes_create_approved.py

Purpose:
Create a Notes.app note after explicit user approval.

Safety:
This tool is NOT dry-run. It should only be called after Lucy has shown a preview
and the user has explicitly approved creation.
"""

from __future__ import annotations

import json
import subprocess
import sys
import time

from notes_dry_run import parse_request


def apple_script_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def create_note(parsed: dict) -> dict:
    info = parsed["parsed"]
    title = info["title"].strip() or "Untitled Note"
    body = info["body"].strip()

    escaped_title = apple_script_escape(title)
    escaped_body = apple_script_escape(body)

    subprocess.run(["/usr/bin/open", "-a", "Notes"], text=True, capture_output=True, timeout=10)
    time.sleep(1.5)

    # Notes can create a note with body; use simple HTML-ish body containing title + body.
    note_body = f"<h1>{escaped_title}</h1><p>{escaped_body}</p>"

    script = f'''
    tell application "Notes"
        activate
        delay 1
        set targetFolder to first folder of default account
        tell targetFolder
            make new note with properties {{name:"{escaped_title}", body:"{note_body}"}}
        end tell
    end tell
    '''

    proc = subprocess.run(
        ["/usr/bin/osascript", "-e", script],
        text=True,
        capture_output=True,
        timeout=30,
    )

    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "osascript failed")

    return {
        "created": True,
        "tool": "notes_create_approved",
        "title": title,
        "body": body,
        "safety_note": "Created only after explicit approval.",
        "osascript_stdout": proc.stdout.strip()
    }


def main() -> int:
    if len(sys.argv) < 2:
        print('Usage: notes_create_approved.py "create a note called Lucy ideas saying add better spider animations"', file=sys.stderr)
        return 2

    request = " ".join(sys.argv[1:])
    parsed = parse_request(request)

    try:
        result = create_note(parsed)
    except Exception as e:
        print(json.dumps({
            "created": False,
            "tool": "notes_create_approved",
            "error": str(e),
            "safety_note": "No note was created if AppleScript failed before completion."
        }, indent=2, ensure_ascii=False))
        return 1

    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
