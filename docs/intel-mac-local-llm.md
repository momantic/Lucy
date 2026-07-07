# Intel Mac local model support

Lucy can run on older non-Apple-Silicon Macs by using a local GGUF model through llama.cpp instead of MLX.

## Provider selection

Lucy reads `data/model_provider.json` and uses `tools/providers/local_llm.py`:

- `arm64` / Apple Silicon: MLX is preferred.
- `x86_64` / Intel Mac: llama.cpp / `llama-cpp-python` is preferred.
- If the preferred provider fails, Lucy can try the configured fallback.

No cloud API is required by this provider layer.

## Setup on Intel Macs

Run:

```zsh
tools/setup_local_llm_intel.sh
```

Then place compatible GGUF files in `assets/models/`, or edit `data/model_provider.json` to point at your model paths.

If you use the setup script's virtual environment, launch Lucy with the same Python so the app can import `llama-cpp-python`:

```zsh
PYTHON="$PWD/.venv-local-llm/bin/python" ./build_lucy_app.sh
PYTHON="$PWD/.venv-local-llm/bin/python" ~/Applications/Lucy.app/Contents/MacOS/Lucy
```

If you prefer launching with Finder or `open`, set the environment for GUI apps first:

```zsh
launchctl setenv PYTHON "$PWD/.venv-local-llm/bin/python"
open ~/Applications/Lucy.app
```

For command-line provider checks, run:

```zsh
"$PWD/.venv-local-llm/bin/python" tools/providers/local_llm.py --status
```

Recommended small models for older Intel Macs:

- `Qwen2.5-1.5B-Instruct` GGUF, quantized around `Q4_K_M`, for chat/drafting.
- `Qwen2.5-Coder-1.5B-Instruct` GGUF for dev/tool-building tasks.

Larger models may work but will be slower and need more RAM.

On older Intel Macs, prefer 1.5B or smaller quantized GGUF models first. If Lucy times out, reduce the model size, lower `LUCY_LLAMA_CONTEXT`, or set `LUCY_LLAMA_THREADS` to a smaller number.

## What remains local

The following Lucy features use the same local provider abstraction:

- normal chat
- email and note drafting
- self-update proposals
- autonomous dev/tool-builder loops
- LinkedIn drafting tools

Apple Silicon users can keep using MLX. Intel users get the same local-first workflow through GGUF models.