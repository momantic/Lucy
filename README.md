Added a self-dev smoke test command /selfdevcheck
Usage: /selfdevcheck
Purpose: Perform a self-dev smoke test to ensure the development environment is functioning correctly.

## Local model compatibility

Lucy now uses an auto-selected local model provider:

- Apple Silicon Macs use MLX by default.
- Intel Macs use a local GGUF model through llama.cpp / llama-cpp-python.
- Cloud APIs remain disabled by default.

For older non-Apple-Silicon Macs, see `docs/intel-mac-local-llm.md` and run:

```zsh
tools/setup_local_llm_intel.sh
```

If you use the Intel setup virtual environment, launch Lucy with `PYTHON` pointing at that environment so local GGUF inference is available inside the app:

```zsh
PYTHON="$PWD/.venv-local-llm/bin/python" ~/Applications/Lucy.app/Contents/MacOS/Lucy
```

For Finder/`open` launches, set the GUI environment first:

```zsh
launchctl setenv PYTHON "$PWD/.venv-local-llm/bin/python"
open ~/Applications/Lucy.app
```

## Private Lucy download tracker

Lucy includes a tiny backend tracker at `backend/download_tracker.py`. It counts
downloads in SQLite, redirects users to the real GitHub release ZIP, and gives
you a token-protected real-time dashboard.

Run locally for testing:

```zsh
LUCY_TRACKER_TOKEN="replace-with-a-long-secret" python3 backend/download_tracker.py
```

Open your private dashboard:

```text
http://127.0.0.1:8787/dashboard?token=replace-with-a-long-secret
```

Public download links should point at:

```text
https://your-tracker-host.example/d/lucy?source=home-hero
```

The static docs keep direct GitHub links by default. To make the buttons and the
install command use the tracker, edit `docs/download-tracker-config.js` and set:

```js
window.LUCY_DOWNLOAD_TRACKER_BASE = "https://your-tracker-host.example";
```