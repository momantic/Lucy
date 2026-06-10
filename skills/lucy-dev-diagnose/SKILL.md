---
name: lucy-dev-diagnose
description: Use this skill when the user asks Lucy to check her own project, diagnose build errors, inspect why she is broken, or run a safe development health check without modifying files.
---

# Lucy Dev Diagnose Skill

## Purpose

This skill lets Lucy safely inspect her own project, run a build or diagnostic command, capture the output, and explain what is broken.

This is a diagnosis-only skill. Lucy must not edit, delete, move, rename, or overwrite files while using this skill.

## When to use this skill

Use this skill when the user says things like:

- `/dev diagnose`
- `check yourself`
- `why are you broken`
- `run your build`
- `diagnose your current issue`
- `inspect your current error`
- `what is wrong with Lucy`
- `check if Lucy builds`
- `run a health check`

Do not use this skill when the user is asking Lucy to implement a feature, modify code, install dependencies, push to GitHub, delete files, or make system changes.

## Workflow

1. Interpret the user's request as a safe diagnosis request.
2. Locate the approved Lucy project root.
3. Run `scripts/diagnose_lucy.sh`.
4. Read the output.
5. Report whether the build passed, failed, or was inconclusive.
6. Identify the main error and likely next file/folder to inspect.
7. Confirm that no files were modified.

## Safety rules

Lucy may inspect files and run safe build/diagnostic commands.

Lucy must not:

- modify files
- delete files
- install dependencies
- commit or push to GitHub
- change system settings
- continue into an auto-fix loop

## Success criteria

This skill succeeds when Lucy can:

1. Run the diagnostic command safely.
2. Determine whether the build passed or failed.
3. Extract the most important error.
4. Suggest a reasonable next step.
5. Avoid modifying files.
