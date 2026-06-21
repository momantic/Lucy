#!/usr/bin/env /usr/local/bin/python3
import importlib.util
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "swift_app" / "Sources"
BINARY = ROOT / "swift_app" / "Lucy"
REPORTS = ROOT / "self_updates"
TASKS = ROOT / "tools" / "dev_tasks"


def swift_files():
    return sorted(SOURCES.glob("*.swift"))


def compile_lucy():
    files = [str(p) for p in swift_files()]
    if not files:
        return False, "No Swift source files found."

    result = subprocess.run(
        ["swiftc", *files, "-o", str(BINARY)],
        cwd=ROOT,
        text=True,
        capture_output=True
    )

    output = (result.stdout + "\n" + result.stderr).strip()
    if not output:
        output = "No compiler output."

    return result.returncode == 0, output


def cmd_status():
    ok, compile_output = compile_lucy()
    REPORTS.mkdir(parents=True, exist_ok=True)

    print("Lucy Dev Agent Status")
    print("=====================")
    print(f"Root: {ROOT}")
    print(f"Swift files: {len(swift_files())}")
    for file in swift_files():
        print(f"- {file.name}")
    print(f"Compile OK: {ok}")
    print(compile_output)


def task_file_for(task_name: str) -> Path:
    safe = task_name.replace("-", "_")
    return TASKS / f"{safe}.py"


def run_task(task_name: str):
    task_file = task_file_for(task_name)

    if not task_file.exists():
        print(f"Unknown apply task: {task_name}")
        print("Available task files:")
        for file in sorted(TASKS.glob("*.py")):
            if file.name not in {"common.py", "__init__.py"}:
                print(f"- {file.stem.replace('_', '-')}")
        sys.exit(1)

    sys.path.insert(0, str(TASKS))

    spec = importlib.util.spec_from_file_location(task_file.stem, task_file)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)

    if not hasattr(module, "run"):
        print(f"Task {task_name} has no run() function.")
        sys.exit(1)

    module.run()


def main():
    if len(sys.argv) < 2:
        print("Usage:")
        print("  /usr/local/bin/python3 tools/lucy_dev_agent.py status")
        print("  /usr/local/bin/python3 tools/lucy_dev_agent.py apply animation-smoother")
        print("  /usr/local/bin/python3 tools/lucy_dev_agent.py apply cute-eyes")
        sys.exit(1)

    command = sys.argv[1].lower()

    if command == "status":
        cmd_status()
    elif command == "apply":
        if len(sys.argv) < 3:
            print("Usage: /usr/local/bin/python3 tools/lucy_dev_agent.py apply <task-name>")
            sys.exit(1)
        run_task(sys.argv[2].lower())
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
