import shutil
import subprocess
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
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


def backup_sources():
    ensure_dirs()
    backup_dir = BACKUPS / f"sources_{now_stamp()}"
    backup_dir.mkdir(parents=True, exist_ok=True)

    for file in swift_files():
        shutil.copy2(file, backup_dir / file.name)

    return backup_dir


def restore_backup(backup_dir: Path):
    for file in backup_dir.glob("*.swift"):
        target = SOURCES / file.name
        shutil.copy2(file, target)


def write_report(title, body):
    ensure_dirs()
    filename = f"dev_agent_{now_stamp()}_{title}.md"
    path = REPORTS / filename
    path.write_text(body)
    return path


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


def replace_function(source_text: str, function_signature: str, new_function_text: str) -> str:
    start = source_text.find(function_signature)
    if start == -1:
        raise ValueError(f"Could not find function signature: {function_signature}")

    brace_start = source_text.find("{", start)
    if brace_start == -1:
        raise ValueError("Could not find opening brace.")

    depth = 0
    end = None

    for i in range(brace_start, len(source_text)):
        ch = source_text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break

    if end is None:
        raise ValueError("Could not find function end.")

    return source_text[:start] + new_function_text + source_text[end:]
