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