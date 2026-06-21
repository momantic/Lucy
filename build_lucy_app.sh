#!/bin/zsh
set -e

cd ~/lucy

mkdir -p dist/Lucy.app/Contents/MacOS
mkdir -p dist/Lucy.app/Contents/Resources

swiftc swift_app/Sources/*.swift -o dist/Lucy.app/Contents/MacOS/Lucy
chmod +x dist/Lucy.app/Contents/MacOS/Lucy

echo "Built dist/Lucy.app"