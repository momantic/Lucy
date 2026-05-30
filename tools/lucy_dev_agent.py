#!/usr/bin/env python3
import json
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "swift_app" / "Sources"
BINARY = ROOT / "swift_app" / "Lucy"
BACKUPS = ROOT / "backups" / "dev_agent"
REPORTS = ROOT / "self_updates"


def now_stamp():
    return datetime.now().strftime("%Y%m%d_%H%M%S")


def ensure_dirs():
    BACKUPS.mkdir(parents=True, exist_ok=True)
    REPORTS.mkdir(parents=True, exist_ok=True)


def swift_files():
    return sorted(SOURCES.glob("*.swift"))


def compile_lucy():
    files = [str(p) for p in swift_files()]
    if not files:
        return False, "No Swift source files found."

    cmd = ["swiftc", *files, "-o", str(BINARY)]
    result = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True)

    output = (result.stdout + "\n" + result.stderr).strip()
    if not output:
        output = "No compiler output."

    return result.returncode == 0, output


def project_status():
    files = swift_files()
    ok, compile_output = compile_lucy()

    status = {
        "root": str(ROOT),
        "source_dir": str(SOURCES),
        "swift_files": [p.name for p in files],
        "swift_file_count": len(files),
        "binary_exists": BINARY.exists(),
        "compile_ok": ok,
        "compile_output": compile_output,
    }

    return status


def write_report(title, body):
    ensure_dirs()
    filename = f"dev_agent_{now_stamp()}_{title}.md"
    path = REPORTS / filename
    path.write_text(body)
    return path


def backup_sources():
    ensure_dirs()
    backup_dir = BACKUPS / f"sources_{now_stamp()}"
    backup_dir.mkdir(parents=True, exist_ok=True)

    for file in swift_files():
        shutil.copy2(file, backup_dir / file.name)

    return backup_dir


def cmd_status():
    status = project_status()

    body = "# Lucy Dev Agent Status\n\n"
    body += f"Root: `{status['root']}`\n\n"
    body += f"Swift files: {status['swift_file_count']}\n\n"
    for file in status["swift_files"]:
        body += f"- {file}\n"

    body += "\n## Compile Check\n\n"
    body += f"Compile OK: `{status['compile_ok']}`\n\n"
    body += "```text\n"
    body += status["compile_output"]
    body += "\n```\n"

    report = write_report("status", body)

    print("Lucy Dev Agent Status")
    print("=====================")
    print(f"Swift files: {status['swift_file_count']}")
    print(f"Compile OK: {status['compile_ok']}")
    print(f"Report: {report}")


def cmd_backup():
    backup_dir = backup_sources()
    print(f"Backup created: {backup_dir}")


def main():
    ensure_dirs()

    if len(sys.argv) < 2:
        print("Usage:")
        print("  python3 tools/lucy_dev_agent.py status")
        print("  python3 tools/lucy_dev_agent.py backup")
        sys.exit(1)

    command = sys.argv[1].lower()

    if command == "status":
        cmd_status()
    elif command == "backup":
        cmd_backup()
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
