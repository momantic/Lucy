#!/bin/zsh
set -e

cd ~/lucy

mkdir -p dist/Lucy.app/Contents/MacOS
mkdir -p dist/Lucy.app/Contents/Resources

swiftc swift_app/Sources/*.swift -o dist/Lucy.app/Contents/MacOS/Lucy
chmod +x dist/Lucy.app/Contents/MacOS/Lucy

echo "Built dist/Lucy.app"


mkdir -p dist/Lucy.app/Contents/Resources
if [ -f assets/appicon/LucyIcon.icns ]; then
  cp assets/appicon/LucyIcon.icns dist/Lucy.app/Contents/Resources/LucyIcon.icns
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile LucyIcon" dist/Lucy.app/Contents/Info.plist 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string LucyIcon" dist/Lucy.app/Contents/Info.plist
fi

