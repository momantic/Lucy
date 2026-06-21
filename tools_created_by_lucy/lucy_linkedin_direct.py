#!/usr/bin/env python3
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
script = ROOT / "tools" / "lucy_linkedin_direct.sh"

result = subprocess.run(
    [str(script)] + sys.argv[1:],
    cwd=str(ROOT),
    text=True,
    capture_output=True,
)

if result.stdout:
    print(result.stdout, end="")
if result.stderr:
    print(result.stderr, end="", file=sys.stderr)

sys.exit(result.returncode)
