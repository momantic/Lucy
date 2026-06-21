#!/usr/bin/env /usr/local/bin/python3
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DYNAMIC_DIR = PROJECT_ROOT / "tools_created_by_lucy" / "dynamic"
REGISTRY = PROJECT_ROOT / "tools_created_by_lucy" / "tool_registry.json"
SANDBOX = PROJECT_ROOT / "tools" / "lucy_tool_sandbox.py"


def slugify(value: str) -> str:
    value = value.lower()
    value = re.sub(r"[^a-z0-9]+", "_", value)
    value = value.strip("_")
    return value[:40] or "dynamic_tool"


def infer_tool_name(description: str) -> str:
    lowered = description.lower()

    if "link" in lowered and ("extract" in lowered or "webpage" in lowered or "url" in lowered):
        return "extract_links"

    if "search" in lowered or "find" in lowered or "web" in lowered or "page" in lowered:
        return "public_web_search"

    return slugify(description)


def generate_safe_tool_code(tool_name: str, description: str) -> str:
    if tool_name == "extract_links":
        return r'''#!/usr/bin/env /usr/local/bin/python3
from __future__ import annotations

import json
import re
import sys
from html.parser import HTMLParser
from urllib.parse import urljoin
from urllib.request import Request, urlopen


class LinkParser(HTMLParser):
    def __init__(self, base_url: str):
        super().__init__()
        self.base_url = base_url
        self.links = []

    def handle_starttag(self, tag, attrs):
        if tag.lower() != "a":
            return
        href = None
        text = ""
        for key, value in attrs:
            if key.lower() == "href":
                href = value
        if href:
            self.links.append(urljoin(self.base_url, href))


def main() -> int:
    if len(sys.argv) < 2:
        print(json.dumps({"ok": False, "error": "Usage: extract_links.py <url>"}))
        return 2

    url = sys.argv[1].strip()
    if not (url.startswith("http://") or url.startswith("https://")):
        url = "https://" + url

    req = Request(url, headers={"User-Agent": "LucyDynamicTool/0.1"})
    with urlopen(req, timeout=8) as resp:
        html = resp.read().decode("utf-8", errors="replace")

    parser = LinkParser(url)
    parser.feed(html)

    print(json.dumps({
        "ok": True,
        "tool": "extract_links",
        "url": url,
        "links": sorted(set(parser.links))[:100]
    }, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'''

    return r'''#!/usr/bin/env /usr/local/bin/python3
from __future__ import annotations

import json
import re
import sys
from urllib.parse import quote_plus


def main() -> int:
    query = " ".join(sys.argv[1:]).strip()
    if not query:
        print(json.dumps({"ok": False, "error": "Usage: public_web_search.py <query>"}))
        return 2

    url = "https://www.google.com/search?q=" + quote_plus(query)

    print(json.dumps({
        "ok": True,
        "tool": "public_web_search",
        "query": query,
        "search_url": url,
        "note": "This V1 dynamic tool returns a safe public search URL. It does not scrape private/authenticated sites."
    }, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'''


def load_registry() -> dict:
    if not REGISTRY.exists():
        return {"tools": []}
    raw = REGISTRY.read_text().strip()
    if not raw:
        return {"tools": []}
    return json.loads(raw)


def save_registry(data: dict) -> None:
    REGISTRY.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def add_or_replace(data: dict, entry: dict) -> None:
    tools = data.setdefault("tools", [])
    by_name = {t.get("name"): t for t in tools}
    by_name[entry["name"]] = entry
    data["tools"] = list(by_name.values())


def run(cmd: list[str], timeout: int = 30) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd,
        cwd=str(PROJECT_ROOT),
        text=True,
        capture_output=True,
        timeout=timeout,
    )


def author_tool(description: str, smoke_arg: str) -> dict:
    DYNAMIC_DIR.mkdir(parents=True, exist_ok=True)

    tool_name = infer_tool_name(description)
    filename = f"{tool_name}.py"
    tool_path = DYNAMIC_DIR / filename

    code = generate_safe_tool_code(tool_name, description)
    tool_path.write_text(code)
    tool_path.chmod(0o755)

    compile_proc = run(["/usr/local/bin/python3", "-m", "py_compile", str(tool_path)])
    if compile_proc.returncode != 0:
        return {
            "ok": False,
            "stage": "py_compile",
            "tool_name": tool_name,
            "stderr": compile_proc.stderr,
            "stdout": compile_proc.stdout,
        }

    sandbox_proc = run(["/usr/local/bin/python3", str(SANDBOX), str(tool_path), smoke_arg], timeout=15)
    if sandbox_proc.returncode != 0:
        return {
            "ok": False,
            "stage": "sandbox_smoke_test",
            "tool_name": tool_name,
            "stdout": sandbox_proc.stdout,
            "stderr": sandbox_proc.stderr,
        }

    registry = load_registry()
    add_or_replace(registry, {
        "name": tool_name,
        "path": f"tools_created_by_lucy/dynamic/{filename}",
        "status": "dynamic_sandbox",
        "dry_run": True,
        "pair_base": tool_name,
        "role": "dry_run",
        "intent_prefixes": [
            f"use {tool_name} ",
            f"{tool_name} ",
        ],
        "purpose": description,
        "requires_approval_for_real_action": False,
        "smoke_test": f'/usr/local/bin/python3 tools/lucy_tool_sandbox.py tools_created_by_lucy/dynamic/{filename} "{smoke_arg}"'
    })
    save_registry(registry)

    return {
        "ok": True,
        "mode": "dynamic_tool_authored",
        "tool_name": tool_name,
        "path": f"tools_created_by_lucy/dynamic/{filename}",
        "registered": True,
        "sandbox_smoke_test": json.loads(sandbox_proc.stdout),
    }


def main() -> int:
    if len(sys.argv) < 2:
        print(json.dumps({
            "ok": False,
            "error": "Usage: lucy_dynamic_tool_author.py '<tool description>' [smoke_arg]"
        }, indent=2))
        return 2

    description = sys.argv[1]
    smoke_arg = sys.argv[2] if len(sys.argv) >= 3 else "test query"

    result = author_tool(description, smoke_arg)
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
