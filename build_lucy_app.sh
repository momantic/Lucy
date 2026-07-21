#!/bin/zsh
set -euo pipefail

# Canonical Lucy app policy:
# - Build exactly one user-facing app at ~/Applications/Lucy.app.
# - Replace the canonical app in-place on every build so Finder/Spotlight show
#   one Lucy app that always contains the latest local updates.
# - Do not leave dist/release Lucy.app bundles behind.

ROOT="${LUCY_ROOT:-$HOME/lucy}"
CANONICAL_APP="${LUCY_APP_PATH:-$HOME/Applications/Lucy.app}"
MACOS_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"
BUILD_ARCHS="${LUCY_BUILD_ARCHS:-$(uname -m)}"
BUNDLE_IDENTIFIER="${LUCY_BUNDLE_IDENTIFIER:-com.momantic.lucy}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
BUILD_DIR="$(mktemp -d)"
APP_PARENT_DIR="$(dirname "$CANONICAL_APP")"

cleanup() {
  rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

cd "$ROOT"

mkdir -p "$APP_PARENT_DIR"
rm -rf "$CANONICAL_APP"
mkdir -p "$CANONICAL_APP/Contents/MacOS"
mkdir -p "$CANONICAL_APP/Contents/Resources"

ARCH_OUTPUTS=()
for ARCH in ${(z)BUILD_ARCHS}; do
  ARCH_OUTPUT="$BUILD_DIR/Lucy-$ARCH"
  swiftc \
    -target "${ARCH}-apple-macos${MACOS_DEPLOYMENT_TARGET}" \
    -sdk "$SDK_PATH" \
    swift_app/Sources/*.swift \
    -o "$ARCH_OUTPUT"
  ARCH_OUTPUTS+=("$ARCH_OUTPUT")
done

if [ ${#ARCH_OUTPUTS[@]} -eq 1 ]; then
  cp "$ARCH_OUTPUTS[1]" "$CANONICAL_APP/Contents/MacOS/Lucy"
else
  lipo -create "${ARCH_OUTPUTS[@]}" -output "$CANONICAL_APP/Contents/MacOS/Lucy"
fi
chmod +x "$CANONICAL_APP/Contents/MacOS/Lucy"

# Bundle Lucy's app icon and runtime resources so Finder, Dock, app switcher,
# and the in-app header all use Lucy's real artwork instead of the default
# blank/white macOS app icon.
cp assets/appicon/LucyIcon.icns "$CANONICAL_APP/Contents/Resources/LucyIcon.icns"
cp lucy-store-icon.png "$CANONICAL_APP/Contents/Resources/LucyStoreIcon.png"
cp -R assets "$CANONICAL_APP/Contents/Resources/assets"
cp -R data "$CANONICAL_APP/Contents/Resources/data"

# Codesign rejects app bundles that contain resource forks/Finder metadata.
# Strip copied extended attributes before signing and packaging.
xattr -cr "$CANONICAL_APP" 2>/dev/null || true

cat > "$CANONICAL_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Lucy</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_IDENTIFIER}</string>
    <key>CFBundleName</key>
    <string>Lucy</string>
    <key>CFBundleDisplayName</key>
    <string>Lucy</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>LucyIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MACOS_DEPLOYMENT_TARGET}</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Lucy uses the microphone only when you click Listen, so she can turn your speech into text in the chat box.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Lucy uses speech recognition only when you click Listen, so she can transcribe your voice request locally into the chat box.</string>
</dict>
</plist>
PLIST

if [ "${LUCY_SKIP_CODESIGN:-0}" != "1" ]; then
  # Sign the executable and bundle so the ZIP preserves a coherent code
  # signature. Public downloads should set LUCY_CODESIGN_IDENTITY to a
  # Developer ID Application certificate and notarize the ZIP.
  codesign --force --sign "${LUCY_CODESIGN_IDENTITY:--}" "$CANONICAL_APP/Contents/MacOS/Lucy"
  codesign --force --sign "${LUCY_CODESIGN_IDENTITY:--}" "$CANONICAL_APP"
fi

touch "$CANONICAL_APP"

echo "Built Lucy app: $CANONICAL_APP"
echo "Architectures: $(lipo -archs "$CANONICAL_APP/Contents/MacOS/Lucy")"
echo "Minimum macOS target: $MACOS_DEPLOYMENT_TARGET"