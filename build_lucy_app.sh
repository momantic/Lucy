#!/bin/zsh
set -euo pipefail

# Canonical Lucy app policy:
# - Build exactly one user-facing app at ~/Applications/Lucy.app.
# - Replace the canonical app in-place on every build so Finder/Spotlight show
#   one Lucy app that always contains the latest local updates.
# - Do not leave dist/release Lucy.app bundles behind.

ROOT="${LUCY_ROOT:-$HOME/lucy}"
CANONICAL_APP="$HOME/Applications/Lucy.app"

cd "$ROOT"

mkdir -p "$HOME/Applications"
rm -rf "$CANONICAL_APP"
mkdir -p "$CANONICAL_APP/Contents/MacOS"
mkdir -p "$CANONICAL_APP/Contents/Resources"

swiftc swift_app/Sources/*.swift -o "$CANONICAL_APP/Contents/MacOS/Lucy"
chmod +x "$CANONICAL_APP/Contents/MacOS/Lucy"

# Bundle Lucy's app icon and runtime resources so Finder, Dock, app switcher,
# and the in-app header all use Lucy's real artwork instead of the default
# blank/white macOS app icon.
cp assets/appicon/LucyIcon.icns "$CANONICAL_APP/Contents/Resources/LucyIcon.icns"
cp lucy-store-icon.png "$CANONICAL_APP/Contents/Resources/LucyStoreIcon.png"
cp -R assets "$CANONICAL_APP/Contents/Resources/assets"
cp -R data "$CANONICAL_APP/Contents/Resources/data"

cat > "$CANONICAL_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Lucy</string>
    <key>CFBundleIdentifier</key>
    <string>com.momantic.lucy</string>
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
    <string>13.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Lucy uses the microphone only when you click Listen, so she can turn your speech into text in the chat box.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Lucy uses speech recognition only when you click Listen, so she can transcribe your voice request locally into the chat box.</string>
</dict>
</plist>
PLIST

touch "$CANONICAL_APP"

# Remove old duplicate app bundles created by earlier build/release flows.
rm -rf "$ROOT/dist/Lucy.app" "$ROOT/release/Lucy-v0.1-beta/Lucy.app"

echo "Built canonical Lucy app: $CANONICAL_APP"