# Structure Steering: Lucy

## Workspace Overview

This repository contains the Lucy Mac desktop companion app, local development tools, browser bridge pieces, generated/self-development logs, release artifacts, and documentation.

Top-level areas:

- `swift_app/` — primary Swift/AppKit desktop app source
- `tools/` — built-in developer tools, scripts, templates, MLX providers, and rendering helpers
- `tools_created_by_lucy/` — sandbox for Lucy-generated tools awaiting promotion
- `browser_bridge/` — local browser bridge server and extension files
- `bridge-extension/` — browser extension package assets
- `data/` — local settings, model-provider config, and installed capability metadata
- `memory/` — local memory files
- `.lucy/` — local agent/self-loop run logs, diagnostics, and generated tool specs/requests
- `self_updates/` — autonomous/self-development reports and build logs
- `roadmap/` — product goals and roadmap data
- `assets/` — icons, model assets, SceneKit/sprite assets
- `docs/` — static website/docs pages
- `release/` and `dist/` — packaged/build outputs
- `archived_ollama_legacy/` — historical Ollama-era code that should remain archived unless explicitly revived

## Important Source Files

- `swift_app/Sources/AppDelegate.swift` — app lifecycle, pet window, movement, moods, hiding/perching/roaming behavior
- `swift_app/Sources/ChatWindowController.swift` — chat UI, commands, routing, approvals, tool execution glue
- `swift_app/Sources/LucyPaths.swift` — root/path resolution for project files
- `swift_app/Sources/LucyRuntime.swift` — runtime status and logging state
- `swift_app/Sources/LucyMLXIntentRouter.swift` — local MLX chat generation
- `swift_app/Sources/LucyMemory.swift` — local memory behavior
- `swift_app/Sources/LucyDevTools.swift` — self-development support
- `tools_created_by_lucy/tool_registry.json` — registry for sandboxed tools and routing metadata
- `tools/lucy_templates/apple_action_tool_pair.md` — template/process for safe Apple-native tool pairs
- `browser_bridge/server.py` — local browser bridge HTTP server
- `instructions.md` — canonical product/safety/self-development instructions

## Duplication Note

There is a nested `Lucy/` directory that appears to mirror much of the top-level project. Treat the current workspace root (`/Users/michaelzheng/Documents/Lucy`) as canonical unless the user explicitly asks to work inside the nested copy.

Before editing duplicated files, confirm which copy is actually used by the build/runtime. The top-level `build_lucy_app.sh` compiles top-level `swift_app/Sources/*.swift`.

## Where to Put Changes

- Swift app behavior: `swift_app/Sources/`
- New sandboxed action tools: `tools_created_by_lucy/`
- Reusable tool templates: `tools/lucy_templates/`
- Built-in maintenance/dev scripts: `tools/`
- Local settings/capabilities: `data/`
- Product/user-facing docs: `docs/` or `README.md` depending on scope
- Steering/context for AI development: `.kiro/steering/`
- Self-development run outputs: `self_updates/` or `.lucy/agent_runs/` as existing conventions indicate

## Files and Directories to Avoid Editing Casually

- `release/` and zip files unless preparing a release
- `dist/` build outputs unless verifying packaging
- `.lucy/agent_runs/`, `.lucy/self_loop_runs/`, `.lucy/diagnostics/`, and `self_updates/` historical logs unless adding a new generated report
- `archived_ollama_legacy/` unless explicitly restoring legacy behavior
- Backup files such as `*.bak-*` unless the task is specifically about migration or cleanup

## Change-Planning Rules

- Inspect relevant files before editing.
- Prefer the smallest safe change that satisfies the user’s goal.
- Keep product, safety, and local-first behavior aligned with `instructions.md`.
- For generated tools, update both the tool file(s) and `tools_created_by_lucy/tool_registry.json` when routing/registration is needed.
- For real-world Apple actions, preserve a preview/approval path.
- For build-affecting Swift changes, verify with `./build_lucy_app.sh` when practical.

## Naming and Organization

- Use descriptive tool names with a clear pair base, e.g. `calendar_dry_run.py` and `calendar_create_approved.py`.
- Prefer explicit `*_dry_run.py` and `*_create_approved.py` naming for action pairs.
- Keep generated candidate tools under `tools_created_by_lucy/dynamic/` or `dynamic/candidate_tools/` until reviewed.
- Keep AppleScript helpers narrowly scoped and callable from shell/Python/Swift wrappers as needed.