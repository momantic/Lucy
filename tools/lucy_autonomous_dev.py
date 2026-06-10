#!/usr/bin/env python3

"""
Lucy Autonomous Dev Engine

This is Lucy's first real agent loop:

goal -> inspect -> plan -> edit -> build -> observe -> fix -> repeat

Safety model:
- Only edits files inside the Lucy project.
- Skips .git, dist, .build, node_modules, backups.
- Does not delete files.
- Does not run arbitrary shell commands from the model.
- Only runs the approved build command.
- Saves logs to self_updates/.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Dict, List, Tuple


PROJECT_ROOT = Path("/Users/michaelzheng/lucy").resolve()

IGNORE_DIRS = {
    ".git",
    ".build",
    "dist",
    "node_modules",
    "__pycache__",
    ".lucy",
}

EDITABLE_EXTENSIONS = {
    ".swift",
    ".py",
    ".json",
    ".md",
    ".sh",
    ".txt",
}

IMPORTANT_PATHS = [
    "README.md",
    "build_lucy_app.sh",
    "swift_app/Sources/ChatWindowController.swift",
]


def now_stamp() -> str:
    return dt.datetime.now().strftime("%Y%m%d_%H%M%S")


def safe_rel(path: Path) -> str:
    return str(path.resolve().relative_to(PROJECT_ROOT))


def is_safe_project_path(path: Path) -> bool:
    try:
        resolved = path.resolve()
        resolved.relative_to(PROJECT_ROOT)
    except Exception:
        return False

    rel_parts = resolved.relative_to(PROJECT_ROOT).parts
    if any(part in IGNORE_DIRS for part in rel_parts):
        return False

    return True


def read_text(path: Path, max_chars: int = 20000) -> str:
    try:
        text = path.read_text(errors="replace")
    except Exception as e:
        return f"[Could not read {path}: {e}]"
    if len(text) > max_chars:
        return text[:max_chars] + "\n\n[TRUNCATED]\n"
    return text


def project_tree(max_files: int = 250) -> str:
    lines = []
    count = 0
    for p in sorted(PROJECT_ROOT.rglob("*")):
        if count >= max_files:
            lines.append("[TRUNCATED TREE]")
            break
        if not p.is_file():
            continue
        if not is_safe_project_path(p):
            continue
        rel = p.relative_to(PROJECT_ROOT)
        if p.suffix not in EDITABLE_EXTENSIONS and p.name not in {"Package.swift"}:
            continue
        lines.append(str(rel))
        count += 1
    return "\n".join(lines)


def collect_context() -> str:
    chunks = []
    chunks.append("PROJECT TREE:\n" + project_tree())

    for rel in IMPORTANT_PATHS:
        p = PROJECT_ROOT / rel
        if p.exists() and p.is_file() and is_safe_project_path(p):
            chunks.append(f"\n\n===== FILE: {rel} =====\n{read_text(p, 18000)}")

    return "\n".join(chunks)


def run_build() -> Tuple[int, str]:
    proc = subprocess.run(
        ["bash", "-lc", "./build_lucy_app.sh"],
        cwd=str(PROJECT_ROOT),
        text=True,
        capture_output=True,
        timeout=180,
    )
    return proc.returncode, proc.stdout + "\n" + proc.stderr


def call_mlx_lm(prompt: str, model: str) -> str:
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
            "2048",
            "--verbose",
            "False",
        ],
        cwd=str(PROJECT_ROOT),
        text=True,
        capture_output=True,
        timeout=600,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr or proc.stdout or "mlx-lm failed")
    return proc.stdout


def extract_json_block(text: str) -> dict:
    # Prefer fenced json.
    m = re.search(r"```json\s*(\{.*?\})\s*```", text, re.S)
    if m:
        return json.loads(m.group(1))

    # Fallback: first full object.
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        return json.loads(text[start:end+1])

    raise ValueError("No JSON object found in model output.")


def validate_edit(rel_path: str, content: str) -> Path:
    if rel_path.startswith("/") or ".." in Path(rel_path).parts:
        raise ValueError(f"Unsafe path: {rel_path}")

    path = (PROJECT_ROOT / rel_path).resolve()

    if not is_safe_project_path(path):
        raise ValueError(f"Path outside allowed project area: {rel_path}")

    if path.suffix not in EDITABLE_EXTENSIONS and path.name != "Package.swift":
        raise ValueError(f"Refusing to edit unsupported file type: {rel_path}")

    if any(part in IGNORE_DIRS for part in path.relative_to(PROJECT_ROOT).parts):
        raise ValueError(f"Refusing to edit ignored path: {rel_path}")

    if len(content) > 250000:
        raise ValueError(f"Refusing oversized file content: {rel_path}")

    return path



def maybe_handle_simple_append(goal: str, dry_run: bool = False) -> bool:
    """
    Deterministic fast path for safe append requests.
    This lets Lucy complete simple autonomous file edits without relying on the model
    to return perfect JSON.
    """
    goal_lower = goal.lower()

    if "readme.md" not in goal_lower:
        return False

    append_markers = ["append", "add", "final line"]
    if not any(marker in goal_lower for marker in append_markers):
        return False

    # Extract text inside single quotes first.
    import re
    m = re.search(r"'([^']+)'", goal)
    if m:
        sentence = m.group(1).strip()
    else:
        # Fallback for: append this exact sentence to README.md: text here
        if ":" not in goal:
            return False
        sentence = goal.split(":", 1)[1].strip().strip('"').strip("'")

    if not sentence:
        return False

    readme = PROJECT_ROOT / "README.md"
    if not is_safe_project_path(readme):
        raise ValueError("README.md path failed safety check.")

    old = readme.read_text(errors="replace") if readme.exists() else ""

    if sentence in old:
        print("Simple append fast path: requested sentence already exists in README.md.")
        return True

    if dry_run:
        print(f"DRY RUN simple append to README.md: {sentence}")
        return True

    new_text = old
    if new_text and not new_text.endswith("\n"):
        new_text += "\n"
    new_text += sentence + "\n"

    readme.write_text(new_text)
    print(f"Simple append fast path: appended to README.md: {sentence}")
    return True



def apply_edits(edits: List[dict], dry_run: bool = False) -> List[str]:
    changed = []

    for edit in edits:
        action = edit.get("action")
        rel_path = edit.get("path")
        content = edit.get("content", "")

        if action not in {"write"}:
            raise ValueError(f"Only write actions are allowed. Got: {action}")

        path = validate_edit(rel_path, content)

        if dry_run:
            changed.append(f"DRY RUN write {rel_path}")
            continue

        path.parent.mkdir(parents=True, exist_ok=True)
        old = path.read_text(errors="replace") if path.exists() else ""
        if old != content:
            path.write_text(content)
            changed.append(f"wrote {rel_path}")

    return changed


def snapshot(paths: List[str], stamp: str) -> Path:
    backup_dir = PROJECT_ROOT / "backups" / f"autonomous_{stamp}"
    backup_dir.mkdir(parents=True, exist_ok=True)

    for rel in paths:
        p = PROJECT_ROOT / rel
        if p.exists() and p.is_file() and is_safe_project_path(p):
            dest = backup_dir / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, dest)

    return backup_dir


def make_prompt(goal: str, context: str, build_output: str | None, attempt: int) -> str:
    if build_output:
        build_section = f"""
PREVIOUS BUILD OUTPUT:
{build_output[-12000:]}
"""
    else:
        build_section = "No build has been run yet for this attempt."

    return f"""
You are a code patch generator for a local user-owned macOS project.

CRITICAL OUTPUT RULE:
Return ONLY one valid JSON object.
Do NOT use markdown.
Do NOT use ``` fences.
Do NOT include explanations before or after the JSON.
Do NOT include comments.
Do NOT include trailing commas.

USER GOAL:
{goal}

ATTEMPT:
{attempt}

RULES:
- You may only write files inside the project.
- You may not delete files.
- You may not rename files.
- You may not run shell commands.
- Prefer the smallest possible change.
- Keep existing behavior unless the user goal requires changing it.
- Do NOT return an empty edits array unless the requested change is already visibly present in the file content.
- If the user asks to append text to README.md, you MUST return exactly one write edit for README.md.
- Use full replacement file contents for every edited file.
- For this test, prefer editing README.md only.

VALID JSON SHAPE:
{{
  "summary": "short summary",
  "edits": [
    {{
      "action": "write",
      "path": "README.md",
      "content": "full new README content here"
    }}
  ],
  "notes": []
}}

BAD OUTPUT EXAMPLES:
- Markdown explanations
- Swift code blocks outside JSON
- Bullet lists outside JSON
- Text before the opening {{
- Text after the closing }}

{build_section}

PROJECT CONTEXT:
{context}

Return ONLY the JSON object now.
""".strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("goal", nargs="+", help="Development goal for Lucy")
    parser.add_argument("--model", default=os.environ.get("LUCY_DEV_MODEL", "mlx-community/Qwen2.5-3B-Instruct-4bit"))
    parser.add_argument("--max-attempts", type=int, default=3)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    goal = " ".join(args.goal)
    stamp = now_stamp()
    log_dir = PROJECT_ROOT / "self_updates"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / f"autonomous_dev_{stamp}.md"

    def log(s: str):
        print(s)
        with log_path.open("a") as f:
            f.write(s + "\n")

    log(f"# Lucy Autonomous Dev Run {stamp}")
    log("")
    log(f"Goal: {goal}")
    log("Provider: mlx")
    log(f"Model: {args.model}")
    log(f"Dry run: {args.dry_run}")
    log("")

    if not (PROJECT_ROOT / "build_lucy_app.sh").exists():
        log("ERROR: build_lucy_app.sh not found.")
        return 2

    # Deterministic safe fast path for simple file operations.
    try:
        if maybe_handle_simple_append(goal, dry_run=args.dry_run):
            code, out = run_build()
            log("Build output:")
            log(out[-4000:])
            if code == 0:
                log("STATUS: PASSED")
                log("Completed via deterministic simple append fast path.")
                return 0
            build_output = out
        else:
            build_output = None
    except Exception as e:
        log(f"ERROR in simple append fast path: {e}")
        return 8

    context = collect_context()
    build_output = None

    for attempt in range(1, args.max_attempts + 1):
        log(f"\n## Attempt {attempt}")

        prompt = make_prompt(goal, context, build_output, attempt)

        try:
            response = call_mlx_lm(prompt, args.model)
        except Exception as e:
            log(f"ERROR calling model: {e}")
            return 3

        raw_path = log_dir / f"autonomous_dev_{stamp}_attempt_{attempt}_raw.txt"
        raw_path.write_text(response)
        log(f"Raw model output saved: {raw_path}")

        try:
            plan = extract_json_block(response)
        except Exception as e:
            log(f"ERROR parsing model JSON: {e}")
            log(response[-4000:])
            return 4

        if not isinstance(plan, dict) or "edits" not in plan:
            log("STATUS: FAILED_BAD_MODEL_SHAPE")
            log("Model returned JSON, but not the required autonomous edit shape.")
            log("Expected keys: summary, edits, notes")
            log(f"Actual keys: {list(plan.keys()) if isinstance(plan, dict) else type(plan)}")
            return 7

        summary = plan.get("summary", "")
        edits = plan.get("edits", [])
        notes = plan.get("notes", [])

        log(f"Model summary: {summary}")
        if notes:
            log("Notes:")
            for n in notes:
                log(f"- {n}")

        if not edits:
            log("Model returned no edits.")

            goal_lower = goal.lower()
            must_edit = (
                "must return" in goal_lower
                or "append" in goal_lower
                or "modify" in goal_lower
                or "add" in goal_lower
                or "write" in goal_lower
            )

            if must_edit:
                log("STATUS: FAILED_NO_EDITS")
                log("The goal required an edit, but the model returned an empty edits array.")
                return 6

            code, out = run_build()
            log("Build output:")
            log(out[-4000:])
            if code == 0:
                log("STATUS: PASSED")
                return 0
            build_output = out
            continue

        paths = [e.get("path", "") for e in edits if e.get("path")]
        backup_dir = snapshot(paths, f"{stamp}_attempt_{attempt}")
        log(f"Backup saved: {backup_dir}")

        try:
            changed = apply_edits(edits, dry_run=args.dry_run)
        except Exception as e:
            log(f"ERROR applying edits: {e}")
            return 5

        if changed:
            log("Changed files:")
            for c in changed:
                log(f"- {c}")
        else:
            log("No file content changed.")

        if args.dry_run:
            log("DRY RUN complete. No files modified.")
            return 0

        code, out = run_build()
        build_output = out

        build_log = log_dir / f"autonomous_dev_{stamp}_attempt_{attempt}_build.log"
        build_log.write_text(out)
        log(f"Build log saved: {build_log}")
        log("Recent build output:")
        log(out[-5000:])

        if code == 0:
            log("")
            log("STATUS: PASSED")
            log("Lucy built successfully after autonomous edits.")
            return 0

        log("STATUS: BUILD_FAILED")
        log("Feeding build failure into next attempt.")

        context = collect_context()

    log("")
    log("STATUS: FAILED_MAX_ATTEMPTS")
    log("Lucy could not complete the goal within the attempt limit.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
