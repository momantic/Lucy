# Apple Action Tool Pair Template

This is Lucy's standard safe pattern for Apple-native tools.

## Purpose

Use this template when Lucy creates a tool that may eventually perform a real Apple/macOS action, such as:
- creating a Reminder
- creating a Calendar event
- drafting Mail
- creating a Note
- running a Shortcut
- opening or organizing Finder items

## Required Files

Each real-world action should usually have two tools:

- tools_created_by_lucy/<tool_name>_dry_run.py
- tools_created_by_lucy/<tool_name>_create_approved.py

Reference examples:

- tools_created_by_lucy/reminders_dry_run.py
- tools_created_by_lucy/reminders_create_approved.py
- tools_created_by_lucy/calendar_dry_run.py
- tools_created_by_lucy/calendar_create_approved.py

## Dry-Run Tool Requirements

The dry-run tool must:
1. Parse the user request.
2. Return JSON.
3. Include dry_run: true.
4. Show a clear preview.
5. Not modify user data.
6. Include a safety_note.

## Approved Creation Tool Requirements

The approved creation tool must:
1. Parse the same user request.
2. Reuse the dry-run parser when possible.
3. Perform the real action only after Lucy receives explicit user approval.
4. Return JSON.
5. Include created: true on success.
6. Fail safely with created: false if AppleScript or the system action fails.
7. Include a safety_note.

## Registry Requirements

Every tool pair must be registered in:

tools_created_by_lucy/tool_registry.json

Each registry entry should include:
- name
- path
- status
- dry_run
- purpose
- requires_approval_for_real_action
- smoke_test

## Swift Integration Pattern

Lucy should use this pattern:

natural request
-> dry-run tool
-> store pending request
-> user approval
-> approved creation tool
-> clear pending request

Real actions must not happen on the first natural-language request.

## Safety Rules

The approved creation tool must never run unless:
1. A dry-run preview was shown.
2. A pending request was stored.
3. The user explicitly approved.

Approval phrases may include:
- yes
- yes create it
- create it
- do it
- confirm
- approved
- yes please

## Verification Requirements

A self-development run using this template should verify:
1. Both tool files exist.
2. Both tool files compile with /usr/local/bin/python3 -m py_compile.
3. tool_registry.json contains both entries.
4. The dry-run smoke test returns JSON.
5. The approved creation tool is not called automatically unless the user explicitly asked for real-action testing.

## Apple-Native Preference

Prefer Apple-native automation:
- AppleScript via osascript
- Shortcuts
- Swift/AppKit
- Calendar.app
- Reminders.app
- Mail.app
- Notes.app
- Finder
- Safari
