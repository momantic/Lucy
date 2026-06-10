#!/usr/bin/env python3

from pathlib import Path
import re
import sys
import subprocess

PROJECT_ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
DIAG_DIR = PROJECT_ROOT / ".lucy" / "diagnostics"

ERROR_PATTERNS = [
    r"error:",
    r"fatal:",
    r"failed",
    r"cannot find",
    r"no such file",
    r"undefined",
    r"missing",
    r"permission denied",
    r"module not found",
    r"build input file cannot be found",
    r"cannot convert",
    r"extra argument",
    r"missing argument",
    r"ambiguous use",
    r"not in scope",
]

SOURCE_EXTENSIONS = {
    ".swift",
    ".py",
    ".js",
    ".ts",
    ".tsx",
    ".json",
    ".md",
    ".sh",
}

IGNORE_DIRS = {
    ".git",
    ".build",
    "dist",
    "node_modules",
    "__pycache__",
}

def latest_log():
    if not DIAG_DIR.exists():
        return None
    logs = sorted(DIAG_DIR.glob("diagnose_*.log"), key=lambda p: p.stat().st_mtime, reverse=True)
    return logs[0] if logs else None

def extract_error_lines(text):
    lines = text.splitlines()
    pattern = re.compile("|".join(ERROR_PATTERNS), re.IGNORECASE)
    hits = []

    for i, line in enumerate(lines, start=1):
        if pattern.search(line):
            hits.append((i, line.strip()))

    return hits[:50]

def extract_file_mentions(text):
    mentions = []

    # Swift/Xcode style file paths often look like:
    # /Users/.../File.swift:123:45: error: ...
    for match in re.finditer(r"([A-Za-z0-9_./~\-]+\.swift):(\d+):?(\d+)?", text):
        mentions.append((match.group(1), match.group(2)))

    # Generic source files
    for match in re.finditer(r"([A-Za-z0-9_./~\-]+\.(py|js|ts|tsx|json|sh|md)):(\d+)?", text):
        mentions.append((match.group(1), match.group(3) or ""))

    # De-dupe while preserving order
    seen = set()
    result = []
    for path, line in mentions:
        key = (path, line)
        if key not in seen:
            seen.add(key)
            result.append((path, line))

    return result[:10]

def extract_missing_symbols(text):
    symbols = []

    patterns = [
        r"cannot find '([^']+)' in scope",
        r"use of unresolved identifier '([^']+)'",
        r"cannot find type '([^']+)' in scope",
        r"no such module '([^']+)'",
        r"undefined symbol: ([A-Za-z0-9_]+)",
    ]

    for pattern in patterns:
        for match in re.finditer(pattern, text, re.IGNORECASE):
            symbols.append(match.group(1))

    seen = set()
    result = []
    for s in symbols:
        if s not in seen:
            seen.add(s)
            result.append(s)
    return result[:10]

def safe_project_files():
    files = []
    for path in PROJECT_ROOT.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(PROJECT_ROOT)
        if any(part in IGNORE_DIRS for part in rel.parts):
            continue
        if path.suffix in SOURCE_EXTENSIONS:
            files.append(path)
    return files[:2000]

def grep_symbol(symbol):
    matches = []
    for path in safe_project_files():
        try:
            text = path.read_text(errors="replace")
        except Exception:
            continue
        if symbol in text:
            rel = path.relative_to(PROJECT_ROOT)
            for idx, line in enumerate(text.splitlines(), start=1):
                if symbol in line:
                    matches.append((str(rel), idx, line.strip()))
                    if len(matches) >= 20:
                        return matches
    return matches

def classify(text):
    lower = text.lower()

    if "status: passed" in lower or "built dist/lucy.app" in lower:
        return "BUILD_PASSED"

    if "no such module" in lower or "module not found" in lower:
        return "MISSING_MODULE"

    if "cannot find" in lower or "not in scope" in lower or "unresolved identifier" in lower:
        return "MISSING_SYMBOL"

    if "no such file" in lower or "build input file cannot be found" in lower:
        return "MISSING_FILE"

    if "permission denied" in lower:
        return "PERMISSION"

    if "argument" in lower or "cannot convert" in lower or "ambiguous use" in lower:
        return "TYPE_OR_SIGNATURE"

    if "error:" in lower:
        return "COMPILER_ERROR"

    return "UNKNOWN"

def print_suggestion(category, error_lines, file_mentions, symbols, log_path, log_text):
    print("========================================")
    print("Lucy Suggested Fix")
    print("========================================")
    print(f"Diagnostic log: {log_path}")
    print(f"Category: {category}")
    print("")
    print("Important error lines:")

    if error_lines:
        for line_no, line in error_lines[:12]:
            print(f"{line_no}: {line}")
    else:
        print("No obvious error lines found.")

    print("")

    if file_mentions:
        print("Files mentioned by the build:")
        for path, line in file_mentions:
            if line:
                print(f"- {path}:{line}")
            else:
                print(f"- {path}")
        print("")

    if symbols:
        print("Symbols/modules mentioned:")
        for symbol in symbols:
            print(f"- {symbol}")
        print("")

        print("Project search results:")
        found_any = False
        for symbol in symbols[:5]:
            matches = grep_symbol(symbol)
            if matches:
                found_any = True
                print(f"\nMatches for `{symbol}`:")
                for rel, line_no, line in matches[:8]:
                    print(f"- {rel}:{line_no}: {line}")
        if not found_any:
            print("No matching references found in scanned source files.")
        print("")

    print("Recommended next step:")

    if category == "BUILD_PASSED":
        print("No fix is needed. Lucy currently builds successfully.")
    elif category == "MISSING_SYMBOL":
        print("A symbol is referenced but Swift cannot find it. Inspect the file mentioned in the first compiler error. The likely fix is one of: restore the missing function/type, correct a typo/rename, or update the reference to the new symbol name.")
    elif category == "MISSING_MODULE":
        print("A module import is missing. Check Package.swift, Xcode settings, or whether the dependency was removed. Do not install anything automatically yet.")
    elif category == "MISSING_FILE":
        print("A file or asset path is missing. Check whether the file was renamed, moved, or never created. If it is an asset, inspect the assets folder and update the path or restore the missing file.")
    elif category == "PERMISSION":
        print("This looks like a permissions issue. If the missing permission is for a script, the likely fix is chmod +x on that script. Do not change permissions outside the Lucy project.")
    elif category == "TYPE_OR_SIGNATURE":
        print("This looks like a function signature or type mismatch. Inspect the first file/line from the compiler error and compare the call site with the function definition.")
    elif category == "COMPILER_ERROR":
        print("Inspect the first compiler error, not the last one. Swift often produces follow-up errors after the first real issue.")
    else:
        print("Read the first meaningful error in the diagnostic log and inspect the file mentioned there.")

    print("")
    print("SAFETY_STATUS: SUGGESTION_ONLY")
    print("No files were modified.")

def main():
    log = latest_log()
    if not log:
        print("SUGGEST_STATUS: INCONCLUSIVE")
        print("No diagnostic log found. Run /dev diagnose first.")
        return 1

    text = log.read_text(errors="replace")
    category = classify(text)
    error_lines = extract_error_lines(text)
    file_mentions = extract_file_mentions(text)
    symbols = extract_missing_symbols(text)

    print_suggestion(category, error_lines, file_mentions, symbols, log, text)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
