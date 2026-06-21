
from __future__ import annotations

def lucy_normalize_intent(request: str) -> str:
    r = request.lower().strip()

    fixes = {
        "linkdin": "linkedin",
        "linkedn": "linkedin",
        "linekdin": "linkedin",
        "alinkedin": "a linkedin",
        "a linkedin": "a linkedin",
        "unsesrtsands": "understands",
        "unesrtsands": "understands",
        "intnetion": "intention",
        "intnet": "intent",
        "wirte": "write",
        "wrtie": "write",
        "wriet": "write",
        "drfat": "draft",
        "drafr": "draft",
        "pst": "post",
        "psot": "post",
        "reserach": "research",
        "serach": "search",
        "seach": "search",
    }

    for bad, good in fixes.items():
        r = r.replace(bad, good)

    # fuzzy LinkedIn phrase detection
    if "linkedin" in r and any(x in r for x in ["post", "draft", "write", "make", "create"]):
        return "linkedin_post"

    return r

#!/usr/bin/env /usr/local/bin/python3


import json
import re
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
REGISTRY = PROJECT_ROOT / "tools_created_by_lucy" / "tool_registry.json"


APP_OPEN_PREFIXES = [
    "open ",
    "launch ",
    "start ",
    "run ",
    "open app ",
    "launch app ",
]


def load_registry() -> dict:
    if not REGISTRY.exists():
        return {"tools": []}

    raw = REGISTRY.read_text().strip()
    if not raw:
        return {"tools": []}

    return json.loads(raw)


def tool_pairs(registry: dict) -> dict[str, dict[str, str]]:
    pairs: dict[str, dict[str, str]] = {}

    for tool in registry.get("tools", []):
        base = tool.get("pair_base")
        role = tool.get("role")
        name = tool.get("name")

        if not base or not role or not name:
            continue

        pairs.setdefault(base, {})
        if role == "dry_run":
            pairs[base]["dry_run"] = name
        elif role == "create_approved":
            pairs[base]["create_approved"] = name

    return {
        base: pair
        for base, pair in pairs.items()
        if pair.get("dry_run") and pair.get("create_approved")
    }


def match_registry_intent(request: str, registry: dict) -> str | None:
    lowered = request.strip().lower()
    best_base = None
    best_len = -1

    pairs = tool_pairs(registry)

    for tool in registry.get("tools", []):
        base = tool.get("pair_base")
        if not base or base not in pairs:
            continue

        for prefix in tool.get("intent_prefixes") or []:
            p = prefix.lower()
            if lowered.startswith(p) and len(p) > best_len:
                best_base = base
                best_len = len(p)

    return best_base


def parse_app_open_request(request: str) -> str | None:
    text = request.strip()

    lowered = text.lower()
    for prefix in APP_OPEN_PREFIXES:
        if lowered.startswith(prefix):
            app = text[len(prefix):].strip()
            app = re.sub(r"\s+for me\s*$", "", app, flags=re.IGNORECASE).strip()
            app = re.sub(r"\s+please\s*$", "", app, flags=re.IGNORECASE).strip()

            # Avoid hijacking URLs; safari_open should handle those.
            if app.startswith("http://") or app.startswith("https://") or "." in app.split()[0]:
                return None

            return app or None

    return None


def run_tool(tool_name: str, request: str) -> tuple[int, str, str]:
    proc = subprocess.run(
        ["/usr/local/bin/python3", str(PROJECT_ROOT / "tools" / "lucy_tool_runner.py"), tool_name, request],
        cwd=str(PROJECT_ROOT),
        text=True,
        capture_output=True,
        timeout=120,
    )
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


def create_app_open_tool_if_needed() -> tuple[bool, str]:
    registry = load_registry()
    pairs = tool_pairs(registry)

    if "app_open" in pairs:
        return True, "app_open tool pair already exists."

    creator = PROJECT_ROOT / "tools" / "lucy_create_app_open_tool.py"
    if not creator.exists():
        return False, (
            "Missing deterministic creator for app_open.\n"
            "Expected: tools/lucy_create_app_open_tool.py"
        )

    proc = subprocess.run(
        ["/usr/local/bin/python3", str(creator)],
        cwd=str(PROJECT_ROOT),
        text=True,
        capture_output=True,
        timeout=120,
    )

    if proc.returncode != 0:
        return False, (
            "Failed to create app_open tool pair.\n"
            f"STDOUT:\n{proc.stdout}\n\nSTDERR:\n{proc.stderr}"
        )

    return True, proc.stdout.strip()


def main() -> int:
    if len(sys.argv) < 2:
        print(json.dumps({
            "ok": False,
            "error": "Usage: lucy_goal_engine.py '<request>'"
        }, indent=2))
        return 2

    request = " ".join(sys.argv[1:]).strip()

    # 0. Explicit tool-authoring request.
    lowered_request = request.lower()
    normalized_intent = lucy_normalize_intent(request)

    # linkedin_direct_draft_route_v2
    if "linkedin" in low and ("post" in low or "draft" in low or "write" in low or "make" in low):
        tool = PROJECT_ROOT / "tools_created_by_lucy" / "lucy_linkedin_direct.py"
        proc = subprocess.run(
            [sys.executable, str(tool), text],
            cwd=str(PROJECT_ROOT),
            capture_output=True,
            text=True,
            timeout=180,
        )
        return {
            "ok": proc.returncode == 0,
            "mode": "lucy_linkedin_direct_v2",
            "stdout": proc.stdout,
            "stderr": proc.stderr,
        }

    # Special-case LinkedIn visible-page research before generic web search.
    if "linkedin" in lowered_request and (
        "research" in lowered_request
        or "read" in lowered_request
        or "summarize" in lowered_request
        or "draft" in lowered_request
        or "post" in lowered_request
        or "trend" in lowered_request
    ):
        if "read visible" in lowered_request or "summarize visible" in lowered_request or "draft from visible" in lowered_request:
            tool = PROJECT_ROOT / "tools_created_by_lucy" / "linkedin_visible_research_read.py"
            topic = request
            for prefix in [
                "read visible linkedin",
                "summarize visible linkedin",
                "draft from visible linkedin",
                "linkedin_visible_research_read",
            ]:
                if topic.lower().startswith(prefix):
                    topic = topic[len(prefix):].strip()
                    break
            if not topic:
                topic = "sea turtles"
        else:
            tool = PROJECT_ROOT / "tools_created_by_lucy" / "linkedin_visible_research_dry_run.py"
            topic = request

        proc = subprocess.run(
            ["/usr/local/bin/python3", str(tool), topic],
            cwd=str(PROJECT_ROOT),
            text=True,
            capture_output=True,
            timeout=60,
        )

        print(json.dumps({
            "ok": proc.returncode == 0,
            "mode": "linkedin_visible_research_v1",
            "pair_base": tool.stem,
            "tool_name": tool.stem,
            "request": request,
            "dry_run_output": proc.stdout.strip(),
            "stderr": proc.stderr.strip(),
            "needs_approval": False,
            "message": "LinkedIn V1 uses Safari visible-page reading only. It does not post automatically."
        }, indent=2, ensure_ascii=False))
        return 0 if proc.returncode == 0 else 1

    wants_tool_creation = (
        "create a tool" in lowered_request
        or "make a tool" in lowered_request
        or "build a tool" in lowered_request
        or "write a tool" in lowered_request
    )

    if wants_tool_creation:
        author = PROJECT_ROOT / "tools" / "lucy_react_toolmaker.py"
        if not author.exists():
            print(json.dumps({
                "ok": False,
                "mode": "dynamic_author_missing",
                "request": request,
                "error": "tools/lucy_dynamic_tool_author.py not found."
            }, indent=2, ensure_ascii=False))
            return 1

        smoke_arg = "https://example.com" if (
            "url" in lowered_request
            or "webpage" in lowered_request
            or "website" in lowered_request
            or "page" in lowered_request
            or "link" in lowered_request
        ) else "ocean animals"

        proc = subprocess.run(
            ["/usr/local/bin/python3", str(author), request, smoke_arg],
            cwd=str(PROJECT_ROOT),
            text=True,
            capture_output=True,
            timeout=120,
        )

        if proc.returncode != 0:
            print(json.dumps({
                "ok": False,
                "mode": "dynamic_author_failed",
                "request": request,
                "stdout": proc.stdout.strip(),
                "stderr": proc.stderr.strip()
            }, indent=2, ensure_ascii=False))
            return 1

        print(proc.stdout.strip())
        return 0

    registry = load_registry()
    pairs = tool_pairs(registry)

    # 1. Existing registered tool intent.
    base = match_registry_intent(request, registry)
    if base and base in pairs:
        dry_tool = pairs[base]["dry_run"]
        approved_tool = pairs[base]["create_approved"]
        code, out, err = run_tool(dry_tool, request)

        print(json.dumps({
            "ok": code == 0,
            "mode": "existing_tool",
            "pair_base": base,
            "dry_run_tool": dry_tool,
            "approved_tool": approved_tool,
            "request": request,
            "dry_run_output": out,
            "stderr": err,
            "needs_approval": True,
            "approval_instruction": "Say 'yes create it' to run the approved action."
        }, indent=2, ensure_ascii=False))
        return 0 if code == 0 else 1

    # 2. Missing known capability: generic app open.
    app_name = parse_app_open_request(request)
    if app_name:
        ok, creation_msg = create_app_open_tool_if_needed()
        if not ok:
            print(json.dumps({
                "ok": False,
                "mode": "missing_capability_failed",
                "capability": "app_open",
                "request": request,
                "error": creation_msg
            }, indent=2, ensure_ascii=False))
            return 1

        registry = load_registry()
        pairs = tool_pairs(registry)
        if "app_open" not in pairs:
            print(json.dumps({
                "ok": False,
                "mode": "created_but_not_registered",
                "capability": "app_open",
                "request": request,
                "creation_output": creation_msg
            }, indent=2, ensure_ascii=False))
            return 1

        dry_tool = pairs["app_open"]["dry_run"]
        approved_tool = pairs["app_open"]["create_approved"]
        code, out, err = run_tool(dry_tool, request)

        print(json.dumps({
            "ok": code == 0,
            "mode": "created_capability_then_dry_run",
            "pair_base": "app_open",
            "dry_run_tool": dry_tool,
            "approved_tool": approved_tool,
            "request": request,
            "capability_creation_output": creation_msg,
            "dry_run_output": out,
            "stderr": err,
            "needs_approval": True,
            "approval_instruction": "Say 'yes create it' to run the approved action."
        }, indent=2, ensure_ascii=False))
        return 0 if code == 0 else 1

    # 3. No capability found: ask Capability Author to create a safe search-style tool.
    author = PROJECT_ROOT / "tools" / "lucy_capability_author.py"
    if author.exists():
        proc = subprocess.run(
            ["/usr/local/bin/python3", str(author), request],
            cwd=str(PROJECT_ROOT),
            text=True,
            capture_output=True,
            timeout=120,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            print(proc.stdout.strip())
            return 0

        print(json.dumps({
            "ok": False,
            "mode": "capability_author_failed",
            "request": request,
            "stdout": proc.stdout.strip(),
            "stderr": proc.stderr.strip()
        }, indent=2, ensure_ascii=False))
        return 1

    print(json.dumps({
        "ok": False,
        "mode": "no_capability",
        "request": request,
        "message": "No registered tool or known capability class matched this request yet."
    }, indent=2, ensure_ascii=False))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
