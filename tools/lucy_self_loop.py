#!/usr/bin/env /usr/local/bin/python3

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path


PROJECT_ROOT = Path("/Users/michaelzheng/lucy").resolve()
SELF_RUNS_DIR = PROJECT_ROOT / ".lucy" / "self_loop_runs"
SELF_RUNS_DIR.mkdir(parents=True, exist_ok=True)


PERMISSION_PATTERNS = [
    "not allowed to send keystrokes",
    "osascript is not allowed",
    "operation not permitted",
    "not authorized",
    "not authorised",
    "tcc",
    "privacy & security > accessibility",
    "privacy & security > automation",
]

SAFETY_PATTERNS = [
    "do not send",
    "did not send",
    "manual approval",
    "irreversible",
    "safety",
]

FIXABLE_PATTERNS = [
    "unknown tool",
    "malformed json",
    "did not return json",
    "missing tool",
    "tool request",
    "traceback",
    "syntaxerror",
    "indentationerror",
    "nameerror",
    "attributeerror",
    "could not find",
    "failed_bad_model_shape",
    "failed_no_edits",
    "typed into",
    "wrong field",
    "ui automation failed",
]


def run(cmd: list[str], timeout: int = 900) -> tuple[int, str]:
    proc = subprocess.run(
        cmd,
        cwd=str(PROJECT_ROOT),
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    out = "\n".join(
        part for part in [proc.stdout.strip(), proc.stderr.strip()] if part
    )
    return proc.returncode, out.strip()


def classify_agent_output(output: str) -> dict:
    lower = output.lower()

    final_match = re.search(r"\nFINAL:\n(?P<final>.*?)(?:\n\nLog:|\Z)", output, flags=re.S)
    final_text = final_match.group("final").strip() if final_match else ""

    if "FINAL:" in output and not any(p in lower for p in FIXABLE_PATTERNS + PERMISSION_PATTERNS):
        return {
            "status": "completed_or_safely_finished",
            "reason": "Agent loop reached final without obvious fixable/permission failure.",
            "final": final_text,
        }

    if any(p in lower for p in PERMISSION_PATTERNS):
        return {
            "status": "permission_blocked",
            "reason": "macOS or OS-level permission blocked the tool. Lucy should not try to bypass this.",
            "final": final_text,
        }

    if "unknown tool" in lower:
        unknowns = re.findall(r"Unknown tool:\s*([A-Za-z0-9_\-]+)", output)

        missing_tool_final = final_text and (
            "missing a required tool" in final_text.lower()
            or "missing required tool" in final_text.lower()
            or "created one tool request" in final_text.lower()
            or "created a tool request" in final_text.lower()
        )

        if final_text and not missing_tool_final:
            return {
                "status": "completed_or_safely_finished",
                "reason": "Agent produced a final answer after recovering from earlier tool errors.",
                "unknown_tools": unknowns,
                "final": final_text,
            }

        return {
            "status": "fixable",
            "reason": "Agent attempted to use an unknown/unregistered tool and did not recover, or stopped after creating a tool request.",
            "unknown_tools": unknowns,
            "final": final_text,
        }

    if "tool request" in lower or ".lucy/tool_requests" in lower:
        return {
            "status": "fixable",
            "reason": "Agent created or referenced a tool request, which may be implementable.",
            "final": final_text,
        }

    if any(p in lower for p in FIXABLE_PATTERNS):
        return {
            "status": "fixable",
            "reason": "Output contains signs of a tool bug or missing capability.",
            "final": final_text,
        }

    return {
        "status": "unknown",
        "reason": "Could not confidently classify the agent result.",
        "final": final_text,
    }


def make_dev_goal(original_goal: str, agent_output: str, classification: dict) -> str:
    # Keep the dev goal bounded. We do not ask autonomous dev to send messages or bypass permissions.
    clipped_output = agent_output[-6000:]

    return f"""
Improve Lucy's local agent/tool system so it can make progress on this user goal:

USER GOAL:
{original_goal}

CLASSIFICATION:
{json.dumps(classification, indent=2)}

AGENT OUTPUT TAIL:
{clipped_output}

Constraints:
- Use MLX/local tooling only.
- Do not add cloud APIs.
- Do not bypass macOS permissions, passwords, privacy prompts, or user consent.
- Do not auto-send iMessages/emails. Communication tools may only prepare drafts for user review.
- Prefer adding or improving a safe local tool in tools/lucy_agent_loop.py or tools/agent_tools.
- Keep changes small and buildable.
- After changes, ./build_lucy_app.sh must pass.
""".strip()


def run_agent(goal: str, max_steps: int) -> tuple[int, str]:
    return run([
        sys.executable,
        "tools/lucy_agent_loop.py",
        goal,
        "--max-steps",
        str(max_steps),
    ])


def run_autonomous_dev(dev_goal: str, max_attempts: int) -> tuple[int, str]:
    return run([
        sys.executable,
        "tools/lucy_autonomous_dev.py",
        dev_goal,
        "--max-attempts",
        str(max_attempts),
    ])


def run_tool_builder(goal: str) -> tuple[int, str]:
    return run([
        sys.executable,
        "tools/lucy_tool_builder.py",
        goal,
    ])


def run_mlx_tool_builder(goal: str) -> tuple[int, str]:
    return run([
        sys.executable,
        "tools/lucy_mlx_tool_builder.py",
        goal,
    ])



def extract_changed_files(dev_output: str) -> list[str]:
    changed: list[str] = []
    in_changed_files = False

    for line in dev_output.splitlines():
        stripped = line.strip()

        if stripped == "Changed files:":
            in_changed_files = True
            continue

        if in_changed_files:
            if not stripped:
                continue

            if not stripped.startswith("- "):
                # Stop reading changed files once we leave the bullet list.
                break

            candidate = stripped[2:].strip()
            candidate = candidate.replace("wrote ", "").replace("changed ", "").strip()

            if candidate:
                changed.append(candidate)

    return list(dict.fromkeys(changed))


def is_real_capability_fix(dev_output: str) -> tuple[bool, str]:
    changed = extract_changed_files(dev_output)

    allowed_prefixes = [
        "tools/lucy_agent_loop.py",
        "tools/lucy_self_loop.py",
        "tools/lucy_autonomous_dev.py",
        "tools/agent_tools/",
        "swift_app/Sources/",
        "skills/",
    ]

    rejected_exact = {
        "README.md",
        "README",
    }

    if not changed:
        return False, "No changed files were detected in the autonomous dev output."

    only_docs_or_notes = True
    for f in changed:
        if f in rejected_exact:
            continue
        if f.endswith(".md") and not f.startswith("skills/"):
            continue
        if f.startswith(".lucy/") or f.startswith("self_updates/") or f.startswith("backups/"):
            continue
        only_docs_or_notes = False

    if only_docs_or_notes:
        return False, f"Only documentation/log files changed: {changed}"

    for f in changed:
        if any(f.startswith(prefix) for prefix in allowed_prefixes):
            return True, f"Capability code appears to have changed: {changed}"

    return False, f"No allowed capability/tool files changed. Changed files: {changed}"



def save_last_goal(goal: str) -> None:
    p = PROJECT_ROOT / ".lucy" / "last_agent_goal.txt"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(goal)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("goal", nargs="+")
    parser.add_argument("--max-cycles", type=int, default=2)
    parser.add_argument("--agent-steps", type=int, default=8)
    parser.add_argument("--dev-attempts", type=int, default=2)
    args = parser.parse_args()

    goal = " ".join(args.goal).strip()
    save_last_goal(goal)

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_path = SELF_RUNS_DIR / f"self_loop_{stamp}.md"

    transcript: list[dict] = []

    print(f"# Lucy Self Loop {stamp}")
    print(f"Goal: {goal}")
    print("")

    for cycle in range(1, args.max_cycles + 1):
        print(f"SELF-LOOP CYCLE {cycle}")
        print("Running agent loop...")
        agent_code, agent_output = run_agent(goal, args.agent_steps)

        print(agent_output)
        print("")

        classification = classify_agent_output(agent_output)

        print("CLASSIFICATION:")
        print(json.dumps(classification, indent=2))
        print("")

        transcript.append({
            "cycle": cycle,
            "agent_code": agent_code,
            "agent_output": agent_output,
            "classification": classification,
        })

        status = classification.get("status")

        if status == "completed_or_safely_finished":
            print("SELF-LOOP FINAL:")
            print(classification.get("final") or "Done.")
            break

        if status == "permission_blocked":
            print("SELF-LOOP FINAL:")
            print(
                "I am blocked by an OS permission, not by missing code. "
                "Please grant the requested macOS permission, then say 'try again'. "
                "I will not try to bypass permissions."
            )
            break

        if status == "fixable":
            if cycle >= args.max_cycles:
                print("SELF-LOOP FINAL:")
                print(
                    "I found a fixable tool/capability issue, but reached my self-improvement cycle limit. "
                    "I stopped safely."
                )
                break

            print("Running deterministic tool builder first...")
            tb_code, tb_output = run_tool_builder(goal)
            print(tb_output)
            print("")

            transcript.append({
                "cycle": cycle,
                "tool_builder_code": tb_code,
                "tool_builder_output": tb_output,
            })

            if "STATUS: PASSED" in tb_output:
                if "Changed files:\n- none" in tb_output or "Changed files:\r\n- none" in tb_output:
                    print("TOOL BUILDER VALIDATION:")
                    print("Tool builder passed. Capability may already exist, so I will retry the original goal.")
                    print("")
                    continue

                real_fix, fix_reason = is_real_capability_fix(tb_output)
                print("TOOL BUILDER VALIDATION:")
                print(fix_reason)
                print("")

                if real_fix:
                    print("Tool builder passed and changed real capability code. Retrying original goal...")
                    print("")
                    continue

            print("Deterministic tool builder could not handle this capability. Trying MLX arbitrary tool builder...")
            mlx_tb_code, mlx_tb_output = run_mlx_tool_builder(goal)
            print(mlx_tb_output)
            print("")

            transcript.append({
                "cycle": cycle,
                "mlx_tool_builder_code": mlx_tb_code,
                "mlx_tool_builder_output": mlx_tb_output,
            })

            if "STATUS: PASSED" in mlx_tb_output:
                if "Changed files:\n- none" in mlx_tb_output or "Changed files:\r\n- none" in mlx_tb_output:
                    print("MLX TOOL BUILDER VALIDATION:")
                    print("MLX tool builder passed. Capability may already exist, so I will retry the original goal.")
                    print("")
                    continue

                real_fix, fix_reason = is_real_capability_fix(mlx_tb_output)
                print("MLX TOOL BUILDER VALIDATION:")
                print(fix_reason)
                print("")

                if real_fix:
                    print("MLX tool builder passed and changed real capability code. Retrying original goal...")
                    print("")
                    continue

            print("MLX tool builder could not safely handle this capability. Falling back to autonomous dev...")

            dev_goal = make_dev_goal(goal, agent_output, classification)
            print("Running autonomous dev to improve tool capability...")
            dev_code, dev_output = run_autonomous_dev(dev_goal, args.dev_attempts)
            print(dev_output)
            print("")

            transcript.append({
                "cycle": cycle,
                "dev_code": dev_code,
                "dev_goal": dev_goal,
                "dev_output": dev_output,
            })

            if "STATUS: PASSED" not in dev_output:
                print("SELF-LOOP FINAL:")
                print(
                    "I tried to improve my tool capability, but the autonomous dev step did not pass. "
                    "I stopped safely."
                )
                break

            real_fix, fix_reason = is_real_capability_fix(dev_output)
            print("SELF-IMPROVEMENT VALIDATION:")
            print(fix_reason)
            print("")

            transcript.append({
                "cycle": cycle,
                "self_improvement_validation": {
                    "real_fix": real_fix,
                    "reason": fix_reason,
                },
            })

            if not real_fix:
                print("SELF-LOOP FINAL:")
                print(
                    "The autonomous dev step passed the build, but it did not appear to change real capability/tool code. "
                    "I rejected the fake fix and stopped safely."
                )
                break

            print("Autonomous dev passed and changed real capability code. Retrying original goal...")
            print("")
            continue

        print("SELF-LOOP FINAL:")
        print(
            classification.get("final")
            or "I could not confidently decide whether this was done, blocked, or self-fixable. I stopped safely."
        )
        break

    log_path.write_text("# Lucy Self Loop Run\n\n" + json.dumps({
        "goal": goal,
        "transcript": transcript,
    }, indent=2, ensure_ascii=False))

    print("")
    print(f"Self-loop log: {log_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
