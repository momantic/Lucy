#!/bin/zsh
set -euo pipefail

ROOT="${LUCY_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
VERSION="${LUCY_RELEASE_VERSION:-v0.1-beta}"
RELEASE_NAME="Lucy-${VERSION}"
RELEASE_DIR="$ROOT/release/$RELEASE_NAME"
ZIP_PATH="$ROOT/release/${RELEASE_NAME}.zip"
MACOS_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"
ALLOW_UNNOTARIZED_RELEASE="${LUCY_ALLOW_UNNOTARIZED_RELEASE:-0}"
KEEP_EXPANDED_RELEASE="${LUCY_KEEP_EXPANDED_RELEASE:-0}"
STAGING_ROOT="$(mktemp -d)"
STAGING_RELEASE_DIR="$STAGING_ROOT/$RELEASE_NAME"
APP_PATH="$STAGING_RELEASE_DIR/Lucy.app"

cleanup() {
  rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

scrub_macos_metadata() {
  local target="$1"

  find "$target" -name '.DS_Store' -delete
  xattr -cr "$target" 2>/dev/null || true

  # Some macOS copies can leave these attributes on app directories even after
  # xattr -c/-cr. Any FinderInfo/resource-fork data inside a signed .app makes
  # codesign/Gatekeeper report the bundle as damaged.
  for attr in \
    com.apple.FinderInfo \
    com.apple.ResourceFork \
    com.apple.quarantine \
    com.apple.provenance
  do
    xattr -dr "$attr" "$target" 2>/dev/null || true
  done
}

require_developer_id_signature() {
  local app="$1"
  local details

  details="$(codesign -dv --verbose=4 "$app" 2>&1)"
  if ! grep -q "Authority=Developer ID Application" <<<"$details"; then
    cat >&2 <<ERROR
Public Lucy releases must be signed with a Developer ID Application certificate.

codesign details for $app did not include:
  Authority=Developer ID Application

Actual signing details:
$details
ERROR
    exit 1
  fi
  if grep -q "Signature=adhoc" <<<"$details"; then
    cat >&2 <<ERROR
Public Lucy releases must not be ad-hoc signed. Ad-hoc signed apps are rejected
by Gatekeeper after browser download and can appear as "damaged".
ERROR
    exit 1
  fi
}

assess_gatekeeper_download() {
  local app="$1"
  local assess_output

  # Simulate the quarantine attribute browsers attach to downloaded ZIP apps.
  # A notarized Developer ID app must still pass this assessment.
  xattr -w com.apple.quarantine \
    '0081;00000000;Chrome;00000000-0000-0000-0000-000000000000' \
    "$app" 2>/dev/null || true

  if ! assess_output="$(spctl --assess --type execute --verbose=4 "$app" 2>&1)"; then
    cat >&2 <<ERROR
Gatekeeper rejected the downloaded-release app. Do not upload this ZIP.

$assess_output
ERROR
    exit 1
  fi

  if ! grep -qi "accepted" <<<"$assess_output"; then
    cat >&2 <<ERROR
Gatekeeper assessment did not report the app as accepted. Do not upload this ZIP.

$assess_output
ERROR
    exit 1
  fi
}

cd "$ROOT"

if [ "$ALLOW_UNNOTARIZED_RELEASE" != "1" ]; then
  if [ -z "${LUCY_CODESIGN_IDENTITY:-}" ] || [ "${LUCY_CODESIGN_IDENTITY:-}" = "-" ] || [ -z "${LUCY_NOTARY_PROFILE:-}" ]; then
    cat >&2 <<ERROR
Refusing to build a public Lucy ZIP without Developer ID signing and notarization.

Chrome-downloaded, unnotarized macOS apps commonly fail Gatekeeper with:
  "Lucy is damaged and can't be opened. You should move it to the Trash."

For a public download, rerun with both:
  LUCY_CODESIGN_IDENTITY="Developer ID Application: ..."
  LUCY_NOTARY_PROFILE="your-notarytool-keychain-profile"

For a private/local QA ZIP only, explicitly opt in:
  LUCY_ALLOW_UNNOTARIZED_RELEASE=1 zsh ./release_lucy_zip.sh
ERROR
    exit 1
  fi
fi

rm -rf "$RELEASE_DIR" "$ZIP_PATH"
mkdir -p "$STAGING_RELEASE_DIR" "$ROOT/release"

LUCY_ROOT="$ROOT" \
LUCY_APP_PATH="$APP_PATH" \
LUCY_BUILD_ARCHS="${LUCY_BUILD_ARCHS:-arm64 x86_64}" \
MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" \
zsh ./build_lucy_app.sh

# Copy runtime files that the downloaded app expects to find next to Lucy.app.
# Use ditto without resource forks/xattrs to avoid Gatekeeper/codesign detritus.
ditto --norsrc --noextattr browser_bridge "$STAGING_RELEASE_DIR/browser_bridge"
ditto --norsrc --noextattr data "$STAGING_RELEASE_DIR/data"
ditto --norsrc --noextattr tools "$STAGING_RELEASE_DIR/tools"
ditto --norsrc --noextattr tools_created_by_lucy "$STAGING_RELEASE_DIR/tools_created_by_lucy"
mkdir -p "$STAGING_RELEASE_DIR/assets/models"
ditto --norsrc --noextattr assets/sprites "$STAGING_RELEASE_DIR/assets/sprites"
ditto --norsrc --noextattr assets/scenekit "$STAGING_RELEASE_DIR/assets/scenekit"
ditto --norsrc --noextattr assets/lucy_icon_1024.png "$STAGING_RELEASE_DIR/assets/lucy_icon_1024.png"
ditto --norsrc --noextattr lucy-store-icon.png "$STAGING_RELEASE_DIR/lucy-store-icon.png"
ditto --norsrc --noextattr install_lucy_local_no_cert.sh "$STAGING_RELEASE_DIR/install_lucy_local_no_cert.sh"

find "$STAGING_RELEASE_DIR" -type f \( -name '*.sh' -o -name '*.py' -o -name '*.applescript' \) -exec chmod +x {} +
scrub_macos_metadata "$STAGING_RELEASE_DIR"

cat > "$STAGING_RELEASE_DIR/README.txt" <<README
Lucy ${VERSION}

Requirements:
- macOS ${MACOS_DEPLOYMENT_TARGET} or newer
- Apple Silicon or Intel 64-bit Mac
- Python 3 for browser bridge mode and optional Intel local-model setup

Open Lucy.app to start Lucy.

For public website downloads, this ZIP must be built with a Developer ID
Application certificate and notarized before uploading. Unnotarized builds are
for private/local QA only and may show "Lucy is damaged and should be moved to
Trash" when downloaded through a browser.

Private/local no-cert repair:
- From this extracted folder, run: zsh ./install_lucy_local_no_cert.sh
- If Finder still blocks opening, run: zsh ./install_lucy_local_no_cert.sh --direct-launch

Intel / older Mac local models:
1. Open Terminal.
2. cd into this folder.
3. Run: tools/setup_local_llm_intel.sh
4. Add a small GGUF model to assets/models or configure data/model_provider.json.

Chrome Bridge:
- Install Lucy Bridge from the Chrome Web Store.
- Run: python3 browser_bridge/server.py
README

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if [ "$ALLOW_UNNOTARIZED_RELEASE" != "1" ]; then
  require_developer_id_signature "$APP_PATH"
fi

if [ -n "${LUCY_NOTARY_PROFILE:-}" ]; then
  echo "Submitting ZIP for notarization with notarytool profile: $LUCY_NOTARY_PROFILE"
  (cd "$STAGING_ROOT" && ditto -c -k --keepParent --norsrc --noextattr "$RELEASE_NAME" "$ZIP_PATH")
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$LUCY_NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  if [ "$ALLOW_UNNOTARIZED_RELEASE" != "1" ]; then
    require_developer_id_signature "$APP_PATH"
    assess_gatekeeper_download "$APP_PATH"
    scrub_macos_metadata "$APP_PATH"
  fi
  rm -f "$ZIP_PATH"
fi

# Build the website ZIP from /tmp staging to avoid repo-folder provenance or
# resource-fork metadata being embedded in public downloads.
(cd "$STAGING_ROOT" && ditto -c -k --keepParent --norsrc --noextattr --zlibCompressionLevel 9 "$RELEASE_NAME" "$ZIP_PATH")
xattr -cr "$ZIP_PATH" 2>/dev/null || true

if [ "$ALLOW_UNNOTARIZED_RELEASE" != "1" ]; then
  VERIFY_ROOT="$(mktemp -d)"
  ditto -x -k "$ZIP_PATH" "$VERIFY_ROOT"
  assess_gatekeeper_download "$VERIFY_ROOT/$RELEASE_NAME/Lucy.app"
  rm -rf "$VERIFY_ROOT"
fi

if [ "$KEEP_EXPANDED_RELEASE" = "1" ]; then
  # Optional inspection copy only. The ZIP above is canonical. On iCloud/File
  # Provider-backed folders, macOS may attach provider metadata to this copy;
  # verify public artifacts by extracting the ZIP into a neutral temp directory.
  ditto --norsrc --noextattr "$STAGING_RELEASE_DIR" "$RELEASE_DIR"
  scrub_macos_metadata "$RELEASE_DIR"
else
  rm -rf "$RELEASE_DIR"
fi

echo "Built release ZIP: $ZIP_PATH"
echo "App architectures: $(lipo -archs "$APP_PATH/Contents/MacOS/Lucy")"
echo "Mach-O minimum OS:"
otool -l "$APP_PATH/Contents/MacOS/Lucy" | awk '/LC_BUILD_VERSION|platform |minos |sdk /{print}'
