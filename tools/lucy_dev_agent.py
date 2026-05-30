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



def restore_backup(backup_dir: Path):
    for file in backup_dir.glob("*.swift"):
        target = SOURCES / file.name
        shutil.copy2(file, target)


def write_apply_report(task_name, backup_dir, compile_ok, compile_output, changed_files, notes):
    body = f"# Lucy Dev Agent Apply Report: {task_name}\n\n"
    body += f"Backup: `{backup_dir}`\n\n"
    body += "## Changed Files\n\n"
    for file in changed_files:
        body += f"- `{file}`\n"

    body += "\n## Notes\n\n"
    body += notes + "\n\n"

    body += "## Compile Result\n\n"
    body += f"Compile OK: `{compile_ok}`\n\n"
    body += "```text\n"
    body += compile_output
    body += "\n```\n"

    return write_report(f"apply_{task_name}", body)


def apply_animation_smoother():
    backup_dir = backup_sources()
    target = SOURCES / "AppDelegate.swift"

    if not target.exists():
        print("Could not find AppDelegate.swift")
        sys.exit(1)

    original = target.read_text()
    updated = original

    replacements = [
        ('withTimeInterval: 0.35', 'withTimeInterval: 0.18'),
        ('withTimeInterval: 2.5', 'withTimeInterval: 2.0'),
        ('withTimeInterval: 6.0', 'withTimeInterval: 5.0'),
    ]

    for old, new in replacements:
        updated = updated.replace(old, new)

    if updated == original:
        print("No animation timing changes were needed.")
        report = write_apply_report(
            "animation_smoother",
            backup_dir,
            True,
            "No source changes were needed.",
            ["swift_app/Sources/AppDelegate.swift"],
            "The animation timing values already appear to be updated."
        )
        print(f"Report: {report}")
        return

    target.write_text(updated)

    ok, compile_output = compile_lucy()

    if not ok:
        restore_backup(backup_dir)
        rollback_ok, rollback_output = compile_lucy()

        report = write_apply_report(
            "animation_smoother_failed",
            backup_dir,
            False,
            compile_output + "\n\nRollback compile OK: " + str(rollback_ok) + "\n" + rollback_output,
            ["swift_app/Sources/AppDelegate.swift"],
            "Compile failed after editing. Sources were rolled back from backup."
        )

        print("Animation smoother update failed. Rolled back.")
        print(f"Report: {report}")
        sys.exit(1)

    report = write_apply_report(
        "animation_smoother",
        backup_dir,
        True,
        compile_output,
        ["swift_app/Sources/AppDelegate.swift"],
        "Updated animation loop timing for smoother movement: animation 0.35s → 0.18s, wander 2.5s → 2.0s, idle mood 6.0s → 5.0s."
    )

    print("Applied animation-smoother update.")
    print(f"Backup: {backup_dir}")
    print(f"Report: {report}")


def main():
    ensure_dirs()

    if len(sys.argv) < 2:
        print("Usage:")
        print("  python3 tools/lucy_dev_agent.py status")
        print("  python3 tools/lucy_dev_agent.py backup")
        print("  python3 tools/lucy_dev_agent.py apply animation-smoother")
        sys.exit(1)

    command = sys.argv[1].lower()

    if command == "status":
        cmd_status()
    elif command == "backup":
        cmd_backup()
    elif command == "apply":
        if len(sys.argv) < 3:
            print("Usage: python3 tools/lucy_dev_agent.py apply animation-smoother")
            sys.exit(1)

        task = sys.argv[2].lower()

        if task == "animation-smoother":
            apply_animation_smoother()
        else:
            print(f"Unknown apply task: {task}")
            sys.exit(1)
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
