#!/usr/bin/env python3

"""Lucy local LLM provider abstraction.

This module keeps Lucy local-first while making model execution portable:

- Apple Silicon (arm64): prefer MLX when available.
- Intel Macs (x86_64): use a local GGUF model through llama.cpp / llama-cpp-python.
- Fallback: if the preferred provider is unavailable, try the configured fallback.

No cloud provider is used here.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[2]
CONFIG_PATH = PROJECT_ROOT / "data" / "model_provider.json"

DEFAULT_CONFIG: dict[str, Any] = {
    "provider": "auto",
    "apple_silicon_provider": "mlx",
    "intel_provider": "llamacpp",
    "fallback_provider": "llamacpp",
    "chat_model": "mlx-community/Qwen2.5-3B-Instruct-4bit",
    "dev_model": "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit",
    "llamacpp_chat_model_path": "assets/models/qwen2.5-1.5b-instruct-q4_k_m.gguf",
    "llamacpp_dev_model_path": "assets/models/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf",
    "allow_cloud": False,
}


class LocalLLMError(RuntimeError):
    """Raised when Lucy cannot reach a configured local model."""


def load_config() -> dict[str, Any]:
    config = dict(DEFAULT_CONFIG)
    if CONFIG_PATH.exists():
        try:
            loaded = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                config.update(loaded)
        except Exception:
            # Keep defaults if config is temporarily malformed.
            pass
    return config


def machine_arch() -> str:
    return platform.machine().lower()


def is_apple_silicon(arch: str | None = None) -> bool:
    return (arch or machine_arch()) in {"arm64", "aarch64"}


def resolve_provider(config: dict[str, Any] | None = None, arch: str | None = None) -> str:
    config = config or load_config()
    provider = str(config.get("provider", "auto")).strip().lower() or "auto"

    if provider != "auto":
        return provider

    # Finder-launched downloaded apps do not inherit the Terminal install
    # shortcut's environment. If the user prepared Lucy's local GGUF/llama.cpp
    # environment in the release folder, honor that portable local path before
    # choosing MLX on Apple Silicon. This keeps older/non-MLX-capable Macs on the
    # compatible provider without requiring a PYTHON=... terminal launch.
    if prepared_llamacpp_runtime(config):
        return str(config.get("intel_provider", "llamacpp")).strip().lower() or "llamacpp"

    if is_apple_silicon(arch):
        return str(config.get("apple_silicon_provider", "mlx")).strip().lower() or "mlx"

    return str(config.get("intel_provider", "llamacpp")).strip().lower() or "llamacpp"


def prepared_llamacpp_runtime(config: dict[str, Any]) -> bool:
    provider = str(config.get("intel_provider", "llamacpp")).strip().lower() or "llamacpp"
    if provider not in {"llamacpp", "llama_cpp", "llama-cpp"}:
        return False

    venv_python = PROJECT_ROOT / ".venv-local-llm" / "bin" / "python"
    if not venv_python.exists():
        return False

    for purpose in ("chat", "dev"):
        try:
            if Path(model_for_purpose(config, provider, purpose)).exists():
                return True
        except LocalLLMError:
            continue

    return False


def model_for_purpose(config: dict[str, Any], provider: str, purpose: str) -> str:
    purpose = (purpose or "chat").lower()
    is_dev = purpose in {"dev", "code", "tool", "tool_builder", "autonomous_dev"}

    if provider == "mlx":
        key = "dev_model" if is_dev else "chat_model"
        return str(config.get(key) or DEFAULT_CONFIG[key])

    if provider in {"llamacpp", "llama_cpp", "llama-cpp"}:
        key = "llamacpp_dev_model_path" if is_dev else "llamacpp_chat_model_path"
        raw = str(config.get(key) or DEFAULT_CONFIG[key])
        path = Path(os.path.expanduser(raw))
        if not path.is_absolute():
            path = PROJECT_ROOT / path
        return str(path)

    raise LocalLLMError(f"Unsupported local provider: {provider}")


def generate_with_mlx(prompt: str, model: str, max_tokens: int, timeout: int) -> str:
    proc = subprocess.run(
        [
            sys.executable,
            "-m",
            "mlx_lm",
            "generate",
            "--model",
            model,
            "--prompt",
            prompt,
            "--max-tokens",
            str(max_tokens),
            "--verbose",
            "False",
        ],
        cwd=str(PROJECT_ROOT),
        text=True,
        capture_output=True,
        timeout=timeout,
    )

    if proc.returncode != 0:
        raise LocalLLMError(proc.stderr or proc.stdout or "mlx-lm failed")

    return proc.stdout.strip()


def generate_with_llamacpp_python(prompt: str, model_path: str, max_tokens: int) -> str:
    try:
        from llama_cpp import Llama  # type: ignore
    except Exception as exc:
        raise LocalLLMError(
            "llama-cpp-python is not installed. On Intel Macs, run tools/setup_local_llm_intel.sh "
            "or install llama-cpp-python into Lucy's Python environment."
        ) from exc

    if not Path(model_path).exists():
        raise LocalLLMError(
            "Local GGUF model not found: "
            f"{model_path}\nPlace a compatible .gguf model there or update data/model_provider.json."
        )

    threads = int(os.environ.get("LUCY_LLAMA_THREADS", max(1, (os.cpu_count() or 4) - 1)))
    context = int(os.environ.get("LUCY_LLAMA_CONTEXT", "4096"))

    llm = Llama(
        model_path=model_path,
        n_ctx=context,
        n_threads=threads,
        verbose=False,
    )
    result = llm(
        prompt,
        max_tokens=max_tokens,
        temperature=float(os.environ.get("LUCY_LLAMA_TEMPERATURE", "0.2")),
        stop=["<|im_end|>", "</s>"],
    )

    choices = result.get("choices") if isinstance(result, dict) else None
    if choices and isinstance(choices, list):
        text = choices[0].get("text", "")
        return str(text).strip()

    return str(result).strip()


def generate_with_llama_cli(prompt: str, model_path: str, max_tokens: int, timeout: int) -> str:
    binary = os.environ.get("LUCY_LLAMA_CLI") or shutil.which("llama-cli") or shutil.which("llama")
    if not binary:
        raise LocalLLMError("No llama.cpp CLI found. Install llama-cpp-python or provide LUCY_LLAMA_CLI.")

    if not Path(model_path).exists():
        raise LocalLLMError(
            "Local GGUF model not found: "
            f"{model_path}\nPlace a compatible .gguf model there or update data/model_provider.json."
        )

    proc = subprocess.run(
        [binary, "-m", model_path, "-p", prompt, "-n", str(max_tokens)],
        cwd=str(PROJECT_ROOT),
        text=True,
        capture_output=True,
        timeout=timeout,
    )

    if proc.returncode != 0:
        raise LocalLLMError(proc.stderr or proc.stdout or "llama.cpp CLI failed")

    return proc.stdout.strip()


def generate_with_llamacpp(prompt: str, model_path: str, max_tokens: int, timeout: int) -> str:
    try:
        return generate_with_llamacpp_python(prompt, model_path, max_tokens)
    except LocalLLMError as python_error:
        try:
            return generate_with_llama_cli(prompt, model_path, max_tokens, timeout)
        except LocalLLMError as cli_error:
            raise LocalLLMError(f"{python_error}\n\nCLI fallback also failed: {cli_error}") from cli_error


def generate(
    prompt: str,
    purpose: str = "chat",
    max_tokens: int = 512,
    provider: str | None = None,
    timeout: int = 600,
) -> str:
    config = load_config()
    selected = (provider or resolve_provider(config)).strip().lower()
    attempted: list[str] = []

    for candidate in [selected, str(config.get("fallback_provider", "")).strip().lower()]:
        if not candidate or candidate in attempted:
            continue
        attempted.append(candidate)

        try:
            model = model_for_purpose(config, candidate, purpose)
            if candidate == "mlx":
                return generate_with_mlx(prompt, model, max_tokens, timeout)
            if candidate in {"llamacpp", "llama_cpp", "llama-cpp"}:
                return generate_with_llamacpp(prompt, model, max_tokens, timeout)
        except Exception as exc:
            last_error = exc
            continue

    raise LocalLLMError(
        "Lucy could not run any configured local model provider. "
        f"Tried: {', '.join(attempted) or '(none)'}. Last error: {last_error}"
    )


def provider_status() -> dict[str, Any]:
    config = load_config()
    selected = resolve_provider(config)
    return {
        "ok": True,
        "arch": machine_arch(),
        "provider": selected,
        "fallback_provider": config.get("fallback_provider"),
        "chat_model_or_path": model_for_purpose(config, selected, "chat"),
        "dev_model_or_path": model_for_purpose(config, selected, "dev"),
        "allow_cloud": bool(config.get("allow_cloud", False)),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Lucy local LLM provider")
    parser.add_argument("--provider", default=None, help="Override provider: auto, mlx, llamacpp")
    parser.add_argument("--purpose", default="chat", help="chat, dev, tool_builder, autonomous_dev")
    parser.add_argument("--max-tokens", type=int, default=512)
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--prompt", default=None)
    parser.add_argument("--prompt-file", default=None)
    parser.add_argument("--stdin", action="store_true", help="Read prompt from stdin")
    parser.add_argument("--status", action="store_true", help="Print provider status JSON")
    args = parser.parse_args()

    if args.status:
        print(json.dumps(provider_status(), indent=2))
        return 0

    if args.stdin:
        prompt = sys.stdin.read()
    elif args.prompt_file:
        prompt = Path(args.prompt_file).read_text(encoding="utf-8", errors="replace")
    elif args.prompt is not None:
        prompt = args.prompt
    else:
        parser.error("Provide --prompt, --prompt-file, or --stdin")

    try:
        print(generate(prompt, purpose=args.purpose, max_tokens=args.max_tokens, provider=args.provider, timeout=args.timeout))
        return 0
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())