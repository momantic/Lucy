#!/usr/bin/env python3

from pathlib import Path
import re
import sys

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
]

def latest_log():
    if not DIAG_DIR.exists():
        return None
    logs = sorted(DIAG_DIR.glob("diagnose_*.log"), key=lambda p: p.stat().st_mtime, reverse=True)
    return logs[0] if logs else None

def extract_error_lines(text):
    lines = text.splitlines()
    hits = []
    pattern = re.compile("|".join(ERROR_PATTERNS), re.IGNORECASE)

    for i, line in enumerate(lines, start=1):
        if pattern.search(line):
            hits.append((i, line.strip()))

    return hits[:40]

def classify(text):
    lower = text.lower()

    if "no such file" in lower or "build input file cannot be found" in lower:
        return (
            "Missing file or asset",
            "Lucy expected a file to exist, but the build could not find it.",
            "Check the file path mentioned in the error. If it is an asset, inspect the assets folder. If it is a Swift file, check whether it was renamed or moved."
        )

    if "cannot find" in lower or "undefined" in lower or "not in scope" in lower:
        return (
            "Missing symbol or renamed code",
            "The code is referencing a function, type, variable, or class that Swift cannot find.",
            "Search for the missing symbol, then inspect the file that references it and the file where it should be defined."
        )

    if "module not found" in lower or "no such module" in lower:
        return (
            "Missing dependency or module",
            "The project is importing a module that is not available to the build system.",
            "Check Package.swift, Xcode build settings, or whether the dependency needs to be installed."
        )

    if "permission denied" in lower:
        return (
            "Permission issue",
            "The build tried to read, write, or execute something without permission.",
            "Check file permissions. For scripts, run chmod +x on the script if appropriate."
        )

    if "syntax error" in lower or "expected" in lower:
        return (
            "Possible syntax error",
            "The compiler likely found malformed Swift code.",
            "Inspect the line number mentioned in the compiler error and check recent edits."
        )

    if "status: passed" in lower or "built dist/lucy.app" in lower:
        return (
            "Build passed",
            "Lucy built successfully.",
            "No fix is needed right now."
        )

    return (
        "Unclassified build issue",
        "The build failed, but the analyzer could not confidently classify the root cause.",
        "Read the first compiler error in the diagnostic output and inspect the file mentioned there."
    )

def main():
    log = latest_log()

    if not log:
        print("SUMMARY_STATUS: INCONCLUSIVE")
        print("No diagnostic log found.")
        return 1

    text = log.read_text(errors="replace")
    error_lines = extract_error_lines(text)
    category, likely_cause, next_step = classify(text)

    print("========================================")
    print("Lucy Diagnosis Summary")
    print("========================================")
    print(f"Latest log: {log}")
    print(f"Category: {category}")
    print("")
    print("Likely cause:")
    print(likely_cause)
    print("")
    print("Suggested next step:")
    print(next_step)
    print("")

    if error_lines:
        print("Important lines:")
        for line_no, line in error_lines[:20]:
            print(f"{line_no}: {line}")
    else:
        print("Important lines:")
        print("No obvious error lines found.")

    if category == "Build passed":
        print("")
        print("SUMMARY_STATUS: PASSED")
        return 0

    print("")
    print("SUMMARY_STATUS: NEEDS_REVIEW")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
