#!/usr/bin/env python3
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROADMAP = ROOT / "roadmap" / "lucy_v1_goals.json"
SOURCES = ROOT / "swift_app" / "Sources"
BINARY = ROOT / "swift_app" / "Lucy"
REPORTS = ROOT / "self_updates"
BACKUPS = ROOT / "backups" / "builder"
MODEL = "qwen2.5:1.5b"

MAX_FILE_CHARS = 18000


def stamp():
    return datetime.now().strftime("%Y%m%d_%H%M%S")


def ensure_dirs():
    REPORTS.mkdir(parents=True, exist_ok=True)
    BACKUPS.mkdir(parents=True, exist_ok=True)


def run(cmd, cwd=ROOT, input_text=None, timeout=120):
    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            input=input_text,
            text=True,
            capture_output=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return False, f"Command timed out after {timeout} seconds: {' '.join(cmd)}"

    output = (result.stdout + "\n" + result.stderr).strip()
    return result.returncode == 0, output or "No output."


def compile_lucy():
    files = sorted(str(p) for p in SOURCES.glob("*.swift"))
    if not files:
        return False, "No Swift files found."
    return run(["swiftc", *files, "-o", str(BINARY)])


def git_diff():
    ok, output = run(["git", "diff", "--", "swift_app/Sources", "tools", "roadmap"])
    return output


def backup_files(files, task_id):
    backup_dir = BACKUPS / f"{stamp()}_{task_id}"
    backup_dir.mkdir(parents=True, exist_ok=True)

    for rel in files:
        src = ROOT / rel
        if src.exists():
            dst = backup_dir / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)

    return backup_dir


def restore_backup(backup_dir):
    for file in backup_dir.rglob("*"):
        if file.is_file():
            rel = file.relative_to(backup_dir)
            dst = ROOT / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(file, dst)


def read_files(files):
    chunks = []
    for rel in files:
        path = ROOT / rel
        if not path.exists():
            chunks.append(f"\n--- {rel} ---\nFILE DOES NOT EXIST\n")
            continue

        text = path.read_text(errors="replace")
        if len(text) > MAX_FILE_CHARS:
            text = text[:MAX_FILE_CHARS] + "\n\n// TRUNCATED FOR BUILDER CONTEXT\n"

        chunks.append(f"\n--- {rel} ---\n{text}\n")

    return "\n".join(chunks)


def ask_ollama_for_patch(task, file_context):
    feedback = ""

    for attempt in range(1, 4):
        prompt = f"""
You are Lucy's local code builder. You are editing a Swift macOS desktop pet project.

Task ID:
{task["id"]}

Goal:
{task["goal"]}

Allowed files:
{json.dumps(task["files"], indent=2)}

Current file contents:
{file_context}

{feedback}

Return ONLY a unified diff patch in git format.
Your output must start with a line like:
diff --git a/swift_app/Sources/File.swift b/swift_app/Sources/File.swift

Rules:
- Only edit allowed files.
- Do not include explanations outside the diff.
- Do not include shell commands.
- Do not say how to compile.
- Keep changes small and compile-safe.
- Preserve existing features.
- Do not delete commands.
- Do not use paid APIs.
- Do not edit files outside the allowed file list.
- The patch must be applicable with git apply.
""".strip()

        ok, output = run(["ollama", "run", MODEL], input_text=prompt, timeout=180)

        if not ok:
            feedback = f"Previous attempt failed to call Ollama: {output}"
            continue

        patch = extract_patch(output)

        if not patch.strip():
            feedback = """
Previous attempt was invalid because it did not return a unified diff patch.
Do not return prose, shell commands, or explanations.
Return only diff --git format.
"""
            continue

        valid, validation_msg = validate_patch_paths(patch, task["files"])
        if not valid:
            feedback = f"""
Previous patch was rejected:
{validation_msg}

Return a new patch that edits only the allowed files.
"""
            continue

        return True, patch

    return False, "Model failed to produce a valid allowed unified diff patch after 3 attempts."


def extract_patch(text):
    text = text.strip()

    # Remove markdown fences if present.
    text = re.sub(r"^```(?:diff|patch)?\s*", "", text)
    text = re.sub(r"\s*```$", "", text)

    # If model included explanation before the patch, start at the first diff marker.
    markers = ["diff --git ", "--- a/", "--- swift_app/", "+++ b/"]
    starts = [text.find(marker) for marker in markers if text.find(marker) != -1]

    if starts:
        text = text[min(starts):]

    # Reject obvious non-patch output.
    if "diff --git" not in text and "--- " not in text and "+++ " not in text:
        return ""

    return text.strip() + "\n"


def validate_patch_paths(patch, allowed_files):
    allowed = set(allowed_files)

    paths = set()
    for line in patch.splitlines():
        if line.startswith("+++ ") or line.startswith("--- "):
            raw = line[4:].strip()
            if raw == "/dev/null":
                continue
            raw = raw.removeprefix("a/").removeprefix("b/")
            paths.add(raw)

    illegal = [p for p in paths if p not in allowed]
    if illegal:
        return False, f"Patch tried to edit disallowed files: {illegal}"

    return True, "Patch paths OK."


def apply_patch(patch):
    proc = subprocess.run(
        ["git", "apply", "--whitespace=fix", "-"],
        cwd=ROOT,
        input=patch,
        text=True,
        capture_output=True,
    )
    output = (proc.stdout + "\n" + proc.stderr).strip()
    return proc.returncode == 0, output or "Patch applied."


def write_report(task_id, body):
    ensure_dirs()
    path = REPORTS / f"builder_{stamp()}_{task_id}.md"
    path.write_text(body)
    return path


def run_task(task):
    task_id = task["id"]
    allowed_files = task["files"]

    print(f"\n=== Builder task: {task_id} ===")
    print(task["goal"])

    backup_dir = backup_files(allowed_files, task_id)
    file_context = read_files(allowed_files)

    patch_ok, patch_or_error = ask_ollama_for_patch(task, file_context)

    report = f"# Lucy Builder Report: {task_id}\n\n"
    report += f"Goal:\n{task['goal']}\n\n"
    report += f"Backup:\n`{backup_dir}`\n\n"

    if not patch_ok:
        report += "## Failed to Generate Patch\n\n"
        report += "```text\n" + patch_or_error + "\n```\n"
        path = write_report(task_id + "_no_patch", report)
        print(f"Failed to generate patch. Report: {path}")
        return False

    patch = patch_or_error
    report += "## Proposed Patch\n\n```diff\n" + patch + "\n```\n\n"

    valid, validation_msg = validate_patch_paths(patch, allowed_files)
    report += f"## Path Validation\n\n{validation_msg}\n\n"

    if not valid:
        path = write_report(task_id + "_bad_paths", report)
        print(f"Rejected patch due to path validation. Report: {path}")
        return False

    apply_ok, apply_output = apply_patch(patch)
    report += "## Apply Result\n\n"
    report += f"Apply OK: `{apply_ok}`\n\n"
    report += "```text\n" + apply_output + "\n```\n\n"

    if not apply_ok:
        restore_backup(backup_dir)
        path = write_report(task_id + "_apply_failed", report)
        print(f"Patch failed to apply. Rolled back. Report: {path}")
        return False

    compile_ok, compile_output = compile_lucy()
    report += "## Compile Result\n\n"
    report += f"Compile OK: `{compile_ok}`\n\n"
    report += "```text\n" + compile_output + "\n```\n\n"

    if not compile_ok:
        restore_backup(backup_dir)
        rollback_ok, rollback_output = compile_lucy()
        report += "## Rollback\n\n"
        report += f"Rollback compile OK: `{rollback_ok}`\n\n"
        report += "```text\n" + rollback_output + "\n```\n"
        path = write_report(task_id + "_compile_failed", report)
        print(f"Compile failed. Rolled back. Report: {path}")
        return False

    diff = git_diff()
    report += "## Final Diff\n\n```diff\n" + diff + "\n```\n"

    path = write_report(task_id + "_success", report)
    print(f"Task succeeded. Report: {path}")
    return True



def custom_task(goal):
    files = [str(p.relative_to(ROOT)) for p in sorted(SOURCES.glob("*.swift"))]

    return {
        "id": "custom-goal-" + stamp(),
        "goal": goal,
        "files": files
    }



def load_roadmap():
    return json.loads(ROADMAP.read_text())


def main():
    ensure_dirs()

    if len(sys.argv) < 2:
        print("Usage:")
        print("  python3 tools/lucy_builder.py run")
        print("  python3 tools/lucy_builder.py one <task-id>")
        print("  python3 tools/lucy_builder.py goal \"your goal here\"")
        sys.exit(1)

    command = sys.argv[1]

    if command == "run":
        tasks = load_roadmap()
        for task in tasks:
            ok = run_task(task)
            if not ok:
                print("Stopping builder because task failed safely.")
                sys.exit(1)
        print("\nLucy builder completed roadmap.")
        sys.exit(0)

    if command == "goal":
        if len(sys.argv) < 3:
            print("Usage: python3 tools/lucy_builder.py goal \"your goal here\"")
            sys.exit(1)

        goal = " ".join(sys.argv[2:]).strip()
        task = custom_task(goal)
        ok = run_task(task)
        sys.exit(0 if ok else 1)

    if command == "one":
        if len(sys.argv) < 3:
            print("Usage: python3 tools/lucy_builder.py one <task-id>")
            sys.exit(1)

        wanted = sys.argv[2]
        tasks = load_roadmap()
        for task in tasks:
            if task["id"] == wanted:
                ok = run_task(task)
                sys.exit(0 if ok else 1)

        print(f"No task found with id: {wanted}")
        sys.exit(1)

    print(f"Unknown command: {command}")
    sys.exit(1)


if __name__ == "__main__":
    main()
