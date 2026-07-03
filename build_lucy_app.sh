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
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
PLIST

touch "$CANONICAL_APP"

# Remove old duplicate app bundles created by earlier build/release flows.
rm -rf "$ROOT/dist/Lucy.app" "$ROOT/release/Lucy-v0.1-beta/Lucy.app"

echo "Built canonical Lucy app: $CANONICAL_APP"