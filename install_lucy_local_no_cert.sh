#!/bin/zsh
set -euo pipefail

# Private/local Lucy installer for Macs without an Apple Developer ID certificate.
#
# This intentionally does not try to create a public Gatekeeper-trusted download.
# Instead it builds or repairs Lucy on the user's own Mac, removes downloaded-file
# quarantine metadata where macOS allows it, ad-hoc signs the local bundle, and
# launches it. macOS may still attach protected provenance metadata after local
# copies; that metadata does not by itself make the ad-hoc signature invalid.

ROOT="${LUCY_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
VERSION="${LUCY_RELEASE_VERSION:-v0.1-beta}"
INSTALL_PARENT="${LUCY_LOCAL_INSTALL_PARENT:-$HOME/Applications}"
SOURCE_APP_PATH="${LUCY_APP_PATH:-$INSTALL_PARENT/Lucy.app}"
ZIP_PATH=""
NO_OPEN="${LUCY_NO_OPEN:-0}"
DIRECT_LAUNCH="${LUCY_DIRECT_LAUNCH:-0}"

usage() {
  cat <<USAGE
Usage:
  zsh ./install_lucy_local_no_cert.sh [--direct-launch|--no-open]
  zsh ./install_lucy_local_no_cert.sh --zip /path/to/Lucy-${VERSION}.zip [--direct-launch|--no-open]

Modes:
  default       Build Lucy from this source checkout into ~/Applications/Lucy.app.
  --zip PATH    Extract a private QA ZIP into ~/Applications/<release>-local.

This is for private/local beta installs without Apple Developer ID notarization.
Public browser downloads still need Developer ID signing + notarization for a
smooth double-click Gatekeeper experience.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --zip)
      if [ $# -lt 2 ]; then
        echo "--zip requires a ZIP path" >&2
        exit 2
      fi
      ZIP_PATH="$2"
      shift 2
      ;;
    --no-open)
      NO_OPEN="1"
      shift
      ;;
    --direct-launch)
      DIRECT_LAUNCH="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

scrub_download_metadata() {
  local target="$1"

  xattr -cr "$target" 2>/dev/null || true
  for attr in \
    com.apple.quarantine \
    com.apple.provenance \
    com.apple.FinderInfo \
    com.apple.ResourceFork
  do
    xattr -dr "$attr" "$target" 2>/dev/null || true
  done
}

adhoc_resign_app() {
  local app="$1"

  if [ ! -d "$app" ]; then
    echo "Lucy app not found: $app" >&2
    exit 1
  fi

  scrub_download_metadata "$app"
  codesign --force --deep --sign - "$app"
  codesign --verify --deep --strict --verbose=2 "$app"
}

launch_app() {
  local app="$1"

  if [ "$NO_OPEN" = "1" ]; then
    echo "Prepared Lucy app without launching: $app"
    return 0
  fi

  if [ "$DIRECT_LAUNCH" = "1" ]; then
    echo "Starting Lucy executable directly: $app/Contents/MacOS/Lucy"
    "$app/Contents/MacOS/Lucy" >/tmp/lucy-local-no-cert.log 2>&1 &
    disown
    echo "Lucy direct-launch log: /tmp/lucy-local-no-cert.log"
    return 0
  fi

  echo "Opening Lucy: $app"
  if open "$app"; then
    return 0
  fi

  cat >&2 <<FALLBACK
macOS LaunchServices refused to open the ad-hoc signed app. Starting Lucy's
executable directly instead. Logs will be written to /tmp/lucy-local-no-cert.log.
FALLBACK
  "$app/Contents/MacOS/Lucy" >/tmp/lucy-local-no-cert.log 2>&1 &
  disown
}

install_from_source() {
  mkdir -p "$(dirname "$SOURCE_APP_PATH")"
  LUCY_ROOT="$ROOT" \
  LUCY_APP_PATH="$SOURCE_APP_PATH" \
  zsh "$ROOT/build_lucy_app.sh"

  adhoc_resign_app "$SOURCE_APP_PATH"
  echo "Installed private no-cert Lucy app: $SOURCE_APP_PATH"
  launch_app "$SOURCE_APP_PATH"
}

repair_extracted_release() {
  local app="$ROOT/Lucy.app"

  scrub_download_metadata "$ROOT"
  adhoc_resign_app "$app"

  echo "Repaired private no-cert Lucy app in extracted folder: $app"
  launch_app "$app"
}

install_from_zip() {
  local zip="$1"
  local tmp release_dir app release_name target_dir

  if [ ! -f "$zip" ]; then
    echo "ZIP not found: $zip" >&2
    exit 1
  fi

  tmp="$(mktemp -d)"

  ditto -x -k "$zip" "$tmp"
  app="$(find "$tmp" -maxdepth 3 -type d -name 'Lucy.app' -print -quit)"
  if [ -z "$app" ]; then
    echo "No Lucy.app found in ZIP: $zip" >&2
    exit 1
  fi

  release_dir="$(dirname "$app")"
  release_name="$(basename "$release_dir")"
  target_dir="${LUCY_LOCAL_ZIP_INSTALL_DIR:-$INSTALL_PARENT/${release_name}-local}"

  mkdir -p "$(dirname "$target_dir")"
  rm -rf "$target_dir"
  ditto --norsrc --noextattr "$release_dir" "$target_dir"

  app="$target_dir/Lucy.app"
  scrub_download_metadata "$target_dir"
  adhoc_resign_app "$app"

  echo "Installed private no-cert Lucy folder: $target_dir"
  rm -rf "$tmp"
  launch_app "$app"
}

if [ -n "$ZIP_PATH" ]; then
  install_from_zip "$ZIP_PATH"
elif [ -x "$ROOT/build_lucy_app.sh" ] && [ -d "$ROOT/swift_app" ]; then
  install_from_source
elif [ -d "$ROOT/Lucy.app" ]; then
  repair_extracted_release
else
  cat >&2 <<ERROR
Could not find a Lucy source checkout or extracted Lucy.app.

Run this script from either:
  - the Lucy source checkout containing build_lucy_app.sh, or
  - an extracted Lucy release folder containing Lucy.app.

You can also pass a ZIP explicitly:
  zsh ./install_lucy_local_no_cert.sh --zip ~/Downloads/Lucy-${VERSION}.zip
ERROR
  exit 1
fi