#!/bin/zsh
set -euo pipefail

ROOT="${LUCY_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
VENV="$ROOT/.venv-local-llm"
MODELS_DIR="$ROOT/assets/models"

echo "Lucy Intel Mac local model setup"
echo "Project: $ROOT"
echo ""
echo "This prepares Lucy's MLX replacement for non-Apple-Silicon Macs:"
echo "- Python virtual environment: $VENV"
echo "- llama-cpp-python for local GGUF inference"
echo "- model folder: $MODELS_DIR"
echo ""
echo "No cloud API keys are required. Model inference stays local."
echo ""

mkdir -p "$MODELS_DIR"

if [ ! -d "$VENV" ]; then
  python3 -m venv "$VENV"
fi

"$VENV/bin/python" -m pip install --upgrade pip
"$VENV/bin/python" -m pip install llama-cpp-python

cat > "$MODELS_DIR/README.md" <<'README'
# Lucy local GGUF models

Intel Macs cannot run Apple MLX. Lucy uses `tools/providers/local_llm.py` to select a compatible local backend.

- Apple Silicon: MLX (`mlx_lm`) by default.
- Intel Mac: llama.cpp / `llama-cpp-python` with a local `.gguf` model.

Recommended Intel model files:

- `qwen2.5-1.5b-instruct-q4_k_m.gguf` for chat/drafting on older Intel Macs.
- `qwen2.5-coder-1.5b-instruct-q4_k_m.gguf` for development/tool-building.

Place those files in this folder or edit `data/model_provider.json` to point to your chosen GGUF paths.

Large model files are intentionally not committed to the repo.
README

if [ -n "${LUCY_GGUF_CHAT_URL:-}" ]; then
  echo "Downloading chat GGUF model from LUCY_GGUF_CHAT_URL..."
  curl -L --fail --show-error -o "$MODELS_DIR/qwen2.5-1.5b-instruct-q4_k_m.gguf" "$LUCY_GGUF_CHAT_URL"
fi

if [ -n "${LUCY_GGUF_DEV_URL:-}" ]; then
  echo "Downloading dev GGUF model from LUCY_GGUF_DEV_URL..."
  curl -L --fail --show-error -o "$MODELS_DIR/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf" "$LUCY_GGUF_DEV_URL"
fi

echo ""
echo "Setup complete. To test provider detection:"
echo "  $VENV/bin/python tools/providers/local_llm.py --status"
echo ""
echo "Lucy now auto-detects this local Python when the app is launched from the same release folder."
echo ""
echo "To force this Python manually, launch Lucy from Terminal with:"
echo "  PYTHON=$VENV/bin/python ./Lucy.app/Contents/MacOS/Lucy"