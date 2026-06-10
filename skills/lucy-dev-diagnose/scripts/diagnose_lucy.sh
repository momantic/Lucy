#!/usr/bin/env bash

set -u

PROJECT_ROOT="${1:-$(pwd)}"
LOG_DIR="$PROJECT_ROOT/.lucy/diagnostics"
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
LOG_FILE="$LOG_DIR/diagnose_$TIMESTAMP.log"

mkdir -p "$LOG_DIR"

echo "========================================"
echo "Lucy Dev Diagnose"
echo "========================================"
echo "Project root: $PROJECT_ROOT"
echo "Log file: $LOG_FILE"
echo "Timestamp: $TIMESTAMP"
echo ""

if [ ! -d "$PROJECT_ROOT" ]; then
  echo "STATUS: FAILED"
  echo "Reason: Project root does not exist."
  exit 2
fi

cd "$PROJECT_ROOT" || {
  echo "STATUS: FAILED"
  echo "Reason: Could not enter project root."
  exit 2
}

echo "Top-level project files:"
find . -maxdepth 2 -type f \
  | sed 's#^\./##' \
  | sort \
  | head -80

echo ""
echo "Detecting build system..."

BUILD_COMMAND=""

if [ -f "build_lucy_app.sh" ]; then
  echo "Detected: Lucy custom build script"
  BUILD_COMMAND="./build_lucy_app.sh"
elif [ -f "swift_app/Package.swift" ]; then
  echo "Detected: Swift Package Manager inside swift_app"
  BUILD_COMMAND="cd swift_app && swift build"
elif [ -f "Package.swift" ]; then
  echo "Detected: Swift Package Manager"
  BUILD_COMMAND="swift build"
elif find . -maxdepth 3 -name "*.xcworkspace" | grep -q .; then
  echo "Detected: Xcode workspace"
  XCODE_WORKSPACE="$(find . -maxdepth 3 -name "*.xcworkspace" | head -1)"
  echo "Note: Workspace detected. Listing schemes first because a scheme may be required."
  BUILD_COMMAND="xcodebuild -workspace \"$XCODE_WORKSPACE\" -list"
elif find . -maxdepth 3 -name "*.xcodeproj" | grep -q .; then
  echo "Detected: Xcode project"
  XCODE_PROJECT="$(find . -maxdepth 3 -name "*.xcodeproj" | head -1)"
  BUILD_COMMAND="xcodebuild -project \"$XCODE_PROJECT\" build"
elif [ -f "package.json" ]; then
  echo "Detected: Node project"
  if command -v npm >/dev/null 2>&1; then
    if npm run | grep -q " build"; then
      BUILD_COMMAND="npm run build"
    elif npm run | grep -q " test"; then
      BUILD_COMMAND="npm test"
    else
      BUILD_COMMAND="npm install --dry-run"
    fi
  else
    echo "STATUS: FAILED"
    echo "Reason: package.json found, but npm is not available."
    exit 3
  fi
elif [ -f "Makefile" ]; then
  echo "Detected: Makefile"
  BUILD_COMMAND="make"
elif [ -f "pyproject.toml" ]; then
  echo "Detected: Python project"
  BUILD_COMMAND="python -m compileall ."
else
  echo "STATUS: INCONCLUSIVE"
  echo "Reason: No known build system detected."
  echo "Looked for: build_lucy_app.sh, swift_app/Package.swift, Package.swift, .xcodeproj, .xcworkspace, package.json, Makefile, pyproject.toml"
  exit 4
fi

echo ""
echo "Build command selected:"
echo "$BUILD_COMMAND"
echo ""

echo "Running build command..."
echo "Full output will be saved to:"
echo "$LOG_FILE"
echo ""

set +e
bash -lc "$BUILD_COMMAND" > "$LOG_FILE" 2>&1
EXIT_CODE=$?
set -e

echo "Build exit code: $EXIT_CODE"
echo ""

if [ "$EXIT_CODE" -eq 0 ]; then
  echo "STATUS: PASSED"
  echo "Build completed successfully."
  echo ""
  echo "Recent build output:"
  tail -40 "$LOG_FILE"
  echo ""
  echo "Running diagnosis summary..."
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  python3 "$SCRIPT_DIR/summarize_diagnosis.py" "$PROJECT_ROOT" || true
  exit 0
fi

echo "STATUS: FAILED"
echo ""
echo "Important error lines:"
grep -nEi "error:|fatal:|failed|exception|cannot find|no such file|undefined|missing|permission denied|module not found|build input file cannot be found" "$LOG_FILE" | head -40 || true

echo ""
echo "Recent build output:"
tail -80 "$LOG_FILE"

echo ""
echo "Diagnostic log saved at:"
echo "$LOG_FILE"

echo ""
echo "Running diagnosis summary..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$SCRIPT_DIR/summarize_diagnosis.py" "$PROJECT_ROOT" || true

exit "$EXIT_CODE"
