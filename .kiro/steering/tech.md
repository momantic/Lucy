# Technical Steering: Lucy

## Primary Stack

- **Desktop app:** Swift + AppKit in `swift_app/Sources/`
- **Local model runtime:** Apple MLX via Python module `mlx_lm`
- **Tooling and automation:** Python, shell scripts, AppleScript, Swift command-line helpers
- **Browser bridge:** Python HTTP server plus browser extension assets in `browser_bridge/`
- **Persistent local data:** JSON files under `data/`, `memory/`, `.lucy/`, and `self_updates/`

## Build and Runtime

- Main build script: `./build_lucy_app.sh`
- Current script compiles Swift sources with `swiftc swift_app/Sources/*.swift -o dist/Lucy.app/Contents/MacOS/Lucy`
- The app resolves its project root through `LucyPaths`, preferring `~/lucy` when available and otherwise falling back to the current workspace/bundle ancestry.
- Build output belongs under `dist/`; compiled binaries and release zips should not be changed unless preparing a release.

## Model Provider Rules

- Keep Lucy local-first.
- Respect `data/model_provider.json`:
  - `provider`: `mlx`
  - `chat_model`: `mlx-community/Qwen2.5-3B-Instruct-4bit`
  - `dev_model`: `mlx-community/Qwen2.5-Coder-7B-Instruct-4bit`
  - `allow_ollama`: `false`
  - `allow_cloud`: `false`
- Legacy Ollama paths are archived/disabled and should not be reintroduced unless explicitly requested.
- If MLX generation fails, surface the error honestly instead of fabricating a model response.

## Swift/AppKit Conventions

- Keep Mac-native behavior in Swift/AppKit where practical.
- Main pet behavior lives in `AppDelegate.swift`, `LucySceneView.swift`, `LucySpriteView.swift`, and related runtime/state files.
- Chat and command routing currently live largely in `ChatWindowController.swift`; prefer small, well-scoped additions and extract helper types only when justified.
- Use `LucyPaths` for project-relative paths instead of hardcoding new root paths.
- Use `LucyRuntime` for runtime status and verbose logging patterns.
- Avoid noisy terminal logging unless gated behind existing verbose/loud settings.

## Tooling Conventions

- New Lucy-created tools start in `tools_created_by_lucy/`.
- Built-in, developer-authored helpers live in `tools/`.
- Experimental/generated templates live in `tools/generated_tool_templates/` or `tools/lucy_templates/`.
- New Apple-native action tools should follow `tools/lucy_templates/apple_action_tool_pair.md`:
  1. Dry-run parser tool
  2. Approved real-action tool
  3. Registry entry in `tools_created_by_lucy/tool_registry.json`
  4. Natural-language routing only after dry-run works
  5. Explicit approval before real action
  6. Verification of the exact user goal

## Safety Gates for Tools

Do not bypass dry-run/approval patterns for actions that affect external apps or user data.

Before promotion into core behavior, each tool should have:

- Clear purpose
- Dry-run mode or preview behavior
- Safety checks
- Smoke test command
- User approval for promotion

## Browser and Web Automation

- Browser preference defaults to Safari in `data/settings.json`.
- Prefer Safari and Apple-native automation before generic browser automation.
- `browser_bridge/server.py` is a local-only bridge on `127.0.0.1:8765` and writes page text to `/tmp/lucy_browser_page.txt`.
- Do not expand bridge access beyond localhost without explicit user approval.

## Testing and Verification

- For Swift/app changes, run `./build_lucy_app.sh` when practical.
- For Python tools, run their declared smoke test from `tool_registry.json` or a minimal equivalent.
- Verification should check the user’s actual goal, not only that the build passed.
- Report changed files, build/test result, verification result, and next suggested step.

## Dependency Discipline

- Prefer system tools already used by the repo: Swift, Python 3, shell, AppleScript, MLX.
- Do not introduce network dependencies, package managers, or cloud services without a clear need and user approval.
- Avoid global installs. If dependencies are needed, keep them local/project-scoped where possible.