#!/usr/bin/env python3
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "self_updates"
BINARY = ROOT / "swift_app" / "Lucy"
SOURCES = ROOT / "swift_app" / "Sources"


ROADMAP = [
    {
        "name": "status",
        "command": ["python3", "tools/lucy_dev_agent.py", "status"],
        "description": "Verify Lucy compiles before autodev starts."
    },
    {
        "name": "animation-smoother",
        "command": ["python3", "tools/lucy_dev_agent.py", "apply", "animation-smoother"],
        "description": "Make animation timing smoother."
    },
    {
        "name": "cute-eyes",
        "command": ["python3", "tools/lucy_dev_agent.py", "apply", "cute-eyes"],
        "description": "Ensure cute eye drawing is applied."
    },
    {
        "name": "better-crawl",
        "command": ["python3", "tools/lucy_dev_agent.py", "apply", "better-crawl"],
        "description": "Ensure better crawl leg animation is applied."
    },
    {
        "name": "cursor-aware",
        "command": ["python3", "tools/lucy_dev_agent.py", "apply", "cursor-aware"],
        "description": "Ensure cursor awareness is applied."
    },
    {
        "name": "natural-commands",
        "command": ["python3", "tools/lucy_dev_agent.py", "apply", "natural-commands"],
        "description": "Ensure natural command routing is applied."
    },
]


def now_stamp():
    return datetime.now().strftime("%Y%m%d_%H%M%S")


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


def run_command(command):
    result = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        capture_output=True
    )

    output = (result.stdout + "\n" + result.stderr).strip()
    if not output:
        output = "No output."

    return result.returncode == 0, output


def write_report(title, body):
    REPORTS.mkdir(parents=True, exist_ok=True)
    path = REPORTS / f"autodev_{now_stamp()}_{title}.md"
    path.write_text(body)
    return path


def run_roadmap():
    print("Lucy Autodev Runner")
    print("===================")
    print(f"Root: {ROOT}")
    print(f"Tasks: {len(ROADMAP)}")
    print()

    full_report = "# Lucy Autodev Roadmap Report\n\n"
    full_report += f"Started: {datetime.now().isoformat()}\n\n"

    for index, task in enumerate(ROADMAP, start=1):
        print(f"[{index}/{len(ROADMAP)}] {task['name']}")
        print(f"  {task['description']}")

        ok, output = run_command(task["command"])

        full_report += f"## Task {index}: {task['name']}\n\n"
        full_report += f"Description: {task['description']}\n\n"
        full_report += f"Command: `{' '.join(task['command'])}`\n\n"
        full_report += f"Command OK: `{ok}`\n\n"
        full_report += "```text\n"
        full_report += output
        full_report += "\n```\n\n"

        if not ok:
            print("  FAILED. Stopping roadmap.")
            report = write_report("roadmap_failed", full_report)
            print(f"Report: {report}")
            sys.exit(1)

        compile_ok, compile_output = compile_lucy()

        full_report += "### Compile Check After Task\n\n"
        full_report += f"Compile OK: `{compile_ok}`\n\n"
        full_report += "```text\n"
        full_report += compile_output
        full_report += "\n```\n\n"

        if not compile_ok:
            print("  COMPILE FAILED. Stopping roadmap.")
            report = write_report("roadmap_compile_failed", full_report)
            print(f"Report: {report}")
            sys.exit(1)

        print("  OK")

    full_report += f"\nFinished: {datetime.now().isoformat()}\n"
    report = write_report("roadmap_complete", full_report)

    print()
    print("Roadmap complete.")
    print(f"Report: {report}")


def main():
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python3 tools/lucy_autodev.py roadmap")
        sys.exit(1)

    command = sys.argv[1].lower()

    if command == "roadmap":
        run_roadmap()
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
