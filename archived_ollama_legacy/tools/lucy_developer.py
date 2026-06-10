#!/usr/bin/env python3
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "swift_app" / "Sources"
TASKS = ROOT / "tools" / "dev_tasks"
REPORTS = ROOT / "self_updates"
MODEL = "qwen2.5:1.5b"


def stamp():
    return datetime.now().strftime("%Y%m%d_%H%M%S")


def safe_slug(text):
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", "_", text)
    text = text.strip("_")
    return text[:48] or "task"


def run(cmd, input_text=None, timeout=180):
    try:
        result = subprocess.run(
            cmd,
            cwd=ROOT,
            input=input_text,
            text=True,
            capture_output=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return False, f"Timed out after {timeout} seconds: {' '.join(cmd)}"

    output = (result.stdout + "\n" + result.stderr).strip()
    return result.returncode == 0, output or "No output."


def swift_files_preview(max_chars=18000):
    chunks = []

    for path in sorted(SOURCES.glob("*.swift")):
        text = path.read_text(errors="replace")
        if len(text) > max_chars:
            text = text[:max_chars] + "\n// TRUNCATED\n"

        chunks.append(f"\n--- {path.relative_to(ROOT)} ---\n{text}")

    return "\n".join(chunks)


def compile_lucy():
    files = [str(p) for p in sorted(SOURCES.glob("*.swift"))]
    if not files:
        return False, "No Swift files found."

    return run(["swiftc", *files, "-o", str(ROOT / "swift_app" / "Lucy")], timeout=120)


def write_report(name, body):
    REPORTS.mkdir(parents=True, exist_ok=True)
    path = REPORTS / f"developer_{stamp()}_{name}.md"
    path.write_text(body)
    return path


def extract_python(text):
    text = text.strip()

    fence = re.search(r"```(?:python|py)?\s*(.*?)```", text, re.DOTALL)
    if fence:
        return fence.group(1).strip() + "\n"

    # If no fence, try raw Python. It must at least import common and define run().
    if "def run()" in text and "from common import" in text:
        return text.strip() + "\n"

    return ""


def validate_task_code(code):
    banned = [
        "sudo",
        "rm -rf /",
        "shutil.rmtree('/')",
        "subprocess.run(['rm'",
        'subprocess.run(["rm"',
        "os.system(",
        "eval(",
        "exec(",
        "socket",
        "requests.",
        "urllib.request",
    ]

    lowered = code.lower()

    for item in banned:
        if item.lower() in lowered:
            return False, f"Banned pattern found: {item}"

    required = [
        "from common import",
        "backup_sources",
        "compile_lucy",
        "write_apply_report",
        "def run()",
    ]

    for item in required:
        if item not in code:
            return False, f"Missing required pattern: {item}"

    if "SOURCES /" not in code:
        return False, "Task must edit files through SOURCES / ..."

    return True, "Task code passed basic validation."


def ask_model_for_task(goal, task_name):
    context = swift_files_preview()

    prompt = f"""
You are Lucy's local developer loop.

The user wants Lucy to improve herself.

Goal:
{goal}

Create ONE Python dev task file for this project.

The file will be saved as:
tools/dev_tasks/{task_name}.py

The task must follow this project's dev-task pattern.

Required imports:
from common import SOURCES, backup_sources, restore_backup, compile_lucy, write_apply_report

Rules:
- Only edit files in swift_app/Sources using SOURCES / "File.swift".
- Always backup first with backup_sources().
- Always compile with compile_lucy().
- Restore backup if compile fails.
- Write a report using write_apply_report().
- Keep the change small.
- Do not use network.
- Do not use sudo.
- Do not delete user files.
- Do not send emails.
- Do not make purchases.
- Do not touch files outside this project.
- Define a run() function.
- Include if __name__ == "__main__": run()
- Return ONLY Python code. No markdown. No explanation.

Current Swift source preview:
{context}
""".strip()

    ok, output = run(["ollama", "run", MODEL], input_text=prompt, timeout=240)

    if not ok:
        return False, output

    code = extract_python(output)

    if not code:
        return False, "Model did not return a valid Python dev task."

    valid, message = validate_task_code(code)

    if not valid:
        return False, message + "\n\nRaw model output:\n" + output[:4000]

    return True, code


def run_dev_task(task_name):
    return run(["python3", "tools/lucy_dev_agent.py", "apply", task_name.replace("_", "-")], timeout=240)


def develop(goal):
    REPORTS.mkdir(parents=True, exist_ok=True)
    TASKS.mkdir(parents=True, exist_ok=True)

    task_name = "generated_" + safe_slug(goal)
    task_file = TASKS / f"{task_name}.py"

    print("Lucy Developer Loop v1")
    print("======================")
    print(f"Goal: {goal}")
    print(f"Task file: {task_file.relative_to(ROOT)}")

    report = f"# Lucy Developer Loop Report\n\nGoal:\n{goal}\n\nTask file:\n`{task_file.relative_to(ROOT)}`\n\n"

    code_ok, code_or_error = ask_model_for_task(goal, task_name)

    if not code_ok:
        report += "## Failed to Generate Valid Dev Task\n\n"
        report += "```text\n" + code_or_error + "\n```\n"
        path = write_report(task_name + "_generation_failed", report)
        print("Failed to generate a valid dev task.")
        print(f"Report: {path}")
        return False

    task_file.write_text(code_or_error)
    report += "## Generated Dev Task\n\n```python\n" + code_or_error + "\n```\n\n"

    run_ok, run_output = run_dev_task(task_name)

    report += "## Dev Task Run\n\n"
    report += f"Run OK: `{run_ok}`\n\n"
    report += "```text\n" + run_output + "\n```\n\n"

    compile_ok, compile_output = compile_lucy()

    report += "## Final Compile\n\n"
    report += f"Compile OK: `{compile_ok}`\n\n"
    report += "```text\n" + compile_output + "\n```\n\n"

    status_ok, status_output = run(["git", "status", "--short"])
    report += "## Git Status\n\n```text\n" + status_output + "\n```\n"

    path = write_report(task_name + ("_success" if run_ok and compile_ok else "_failed"), report)

    if run_ok and compile_ok:
        print("Developer loop succeeded.")
    else:
        print("Developer loop failed or produced a non-compiling result.")

    print(f"Report: {path}")
    return run_ok and compile_ok


def main():
    if len(sys.argv) < 2:
        print('Usage: python3 tools/lucy_developer.py "goal here"')
        sys.exit(1)

    goal = " ".join(sys.argv[1:]).strip()
    ok = develop(goal)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
