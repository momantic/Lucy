#!/usr/bin/env /usr/local/bin/python3

from __future__ import annotations

import argparse

try:
    from .local_llm import generate as generate_local
except Exception:  # pragma: no cover - direct script execution fallback
    from local_llm import generate as generate_local


DEFAULT_MODEL = "mlx-community/Qwen2.5-3B-Instruct-4bit"


def generate(prompt: str, model: str = DEFAULT_MODEL, max_tokens: int = 2048) -> str:
    return generate_local(prompt, purpose="chat", max_tokens=max_tokens, provider="mlx")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--max-tokens", type=int, default=2048)
    parser.add_argument("--prompt", required=True)
    args = parser.parse_args()

    print(generate(args.prompt, model=args.model, max_tokens=args.max_tokens))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
