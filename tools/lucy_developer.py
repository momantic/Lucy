#!/usr/bin/env /usr/local/bin/python3
import sys
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
agent = root / "tools" / "lucy_dev_agent.py"

if not agent.exists():
    raise SystemExit(f"Missing expected dev agent: {agent}")

args = sys.argv[1:]

# Compatibility mode:
# Old Lucy calls: /usr/local/bin/python3 tools/lucy_developer.py "<freeform goal>"
# Current dev agent expects: /usr/local/bin/python3 tools/lucy_dev_agent.py apply <task-name>
#
# For now, pass known slash-command typo task to a task name if supported;
# otherwise show a clear error instead of pretending it worked.
if len(args) == 1 and "slash commands typo" in args[0].lower():
    cmd = [sys.executable, str(agent), "apply", "slash-command-typo-tolerance"]
else:
    cmd = [sys.executable, str(agent), *args]

raise SystemExit(subprocess.call(cmd, cwd=str(root)))
