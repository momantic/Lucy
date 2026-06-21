# Lucy-Created Tools

This folder is the sandbox for tools Lucy creates during self-development.

Tools start here before they are promoted into built-in Lucy commands.

## Requirements Before Promotion

Each Lucy-created tool should have:

1. A clear purpose
2. A dry-run mode
3. Safety checks
4. At least one smoke test
5. User approval before promotion into the main app

## Dry-Run Mode

A dry-run mode previews what the tool would do without changing the system.

Examples:
- preview a Calendar event without creating it
- preview an email without sending it
- preview a file operation without moving or deleting files

## Safety Checks

Tools should check whether an action is risky before running.

Lucy must ask before:
- sending emails
- creating real calendar events
- deleting files
- installing apps
- spending money
- changing system settings
- uploading data

## Smoke Tests

Each tool should include a small test that proves the basic path works.

Examples:
- parse a reminder request
- generate a calendar event preview
- open an app in dry-run mode
- validate required input fields

## Apple-Native Direction

Prefer Mac and Apple-native automation:

- Swift / AppKit
- AppleScript via osascript
- Shortcuts
- Calendar.app
- Mail.app
- Reminders.app
- Notes.app
- Safari
- Finder

Lucy should remain local-first, safe, and Mac-native.
