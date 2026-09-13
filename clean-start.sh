#!/bin/bash
set -euo pipefail

# Resolve paths relative to this script, regardless of the caller's directory.
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$PROJECT_DIR/BendyFreeApp"
BUNDLE="$PACKAGE_DIR/dist/BendyFree.app"
INSTALLED_APP="/Applications/BendyFree.app"

echo "Stopping BendyFree…"
pkill -x BendyFree || true

echo "Cleaning, testing, and building…"
swift package --package-path "$PACKAGE_DIR" clean
swift test --package-path "$PACKAGE_DIR"
swift build --package-path "$PACKAGE_DIR" -c release
BIN_DIR="$(swift build --package-path "$PACKAGE_DIR" -c release --show-bin-path)"
test -x "$BIN_DIR/BendyFree"

echo "Preparing the replacement app…"
rm -rf -- "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
cp "$BIN_DIR/BendyFree" "$BUNDLE/Contents/MacOS/BendyFree"
cp "$PACKAGE_DIR/Info.plist" "$BUNDLE/Contents/Info.plist"
codesign --force --sign - "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"

# Authenticate before removing installed copies. Preferences and permissions remain.
echo "Installing to /Applications (your Mac password may be required)…"
sudo -v
sudo rm -rf -- "$INSTALLED_APP"
sudo ditto "$BUNDLE" "$INSTALLED_APP"
codesign --verify --deep --strict "$INSTALLED_APP"
rm -rf -- "$PACKAGE_DIR/BendyFree.app" "$HOME/Applications/BendyFree.app"

echo "Launching BendyFree…"
open "$INSTALLED_APP"
echo "Use Allow Screen Recording… if needed, then try Test Fold before the hardware sensor."
