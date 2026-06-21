#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import time

from mail_draft_dry_run import parse_request


def apple_script_escape(value: str) -> str:
    return value.replace("\\\\", "\\\\\\\\").replace("\"", "\\\"")


def create_draft(parsed: dict) -> dict:
    info = parsed["parsed"]
    to = info.get("to", "").strip()
    subject = info.get("subject", "No subject").strip() or "No subject"
    body = info.get("body", "").strip()

    if not to:
        raise ValueError("Recipient email is empty.")

    escaped_to = apple_script_escape(to)
    escaped_subject = apple_script_escape(subject)
    escaped_body = apple_script_escape(body)

    subprocess.run(["/usr/bin/open", "-a", "Mail"], text=True, capture_output=True, timeout=10)
    time.sleep(1.5)

    script = f"""
    tell application "Mail"
        activate
        delay 1
        set newMessage to make new outgoing message with properties {{subject:"{escaped_subject}", content:"{escaped_body}", visible:true}}
        tell newMessage
            make new to recipient at end of to recipients with properties {{address:"{escaped_to}"}}
        end tell
    end tell
    """

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
        "tool": "mail_draft_create_approved",
        "to": to,
        "subject": subject,
        "body": body,
        "safety_note": "Created Mail.app draft only after explicit approval.",
        "osascript_stdout": proc.stdout.strip()
    }


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: mail_draft_create_approved.py 'write an email to johndoe@example.com subject Hello saying testing Lucy mail draft'", file=sys.stderr)
        return 2

    request = " ".join(sys.argv[1:])
    parsed = parse_request(request)

    try:
        result = create_draft(parsed)
    except Exception as e:
        print(json.dumps({
            "created": False,
            "tool": "mail_draft_create_approved",
            "error": str(e),
            "safety_note": "No Mail.app draft was created if AppleScript failed before completion."
        }, indent=2, ensure_ascii=False))
        return 1

    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
