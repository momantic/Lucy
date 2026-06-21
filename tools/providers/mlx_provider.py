#!/usr/bin/env /usr/local/bin/python3

from __future__ import annotations

import argparse
import subprocess
import sys


DEFAULT_MODEL = "mlx-community/Qwen2.5-3B-Instruct-4bit"


def generate(prompt: str, model: str = DEFAULT_MODEL, max_tokens: int = 2048) -> str:
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
        text=True,
        capture_output=True,
        timeout=600,
    )

    if proc.returncode != 0:
        raise RuntimeError(proc.stderr or proc.stdout or "mlx-lm failed")

    return proc.stdout.strip()


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
