#!/bin/bash
set -euo pipefail

# Builds a fresh release app and packages it as site/BendyFree.dmg.
# Set SIGN_IDENTITY (see `security find-identity -v -p codesigning`) to sign with a stable identity.
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$PROJECT_DIR/BendyFreeApp"
BUNDLE="$PACKAGE_DIR/dist/BendyFree.app"
STAGING="$PACKAGE_DIR/dist/dmg-staging"
DMG="$PROJECT_DIR/site/BendyFree.dmg"

swift build --package-path "$PACKAGE_DIR" -c release
BIN_DIR="$(swift build --package-path "$PACKAGE_DIR" -c release --show-bin-path)"

rm -rf -- "$BUNDLE" "$STAGING"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources" "$STAGING"
cp "$BIN_DIR/BendyFree" "$BUNDLE/Contents/MacOS/BendyFree"
cp "$PACKAGE_DIR/Info.plist" "$BUNDLE/Contents/Info.plist"
cp "$PACKAGE_DIR/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
codesign --force --sign "${SIGN_IDENTITY:--}" "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"

ditto "$BUNDLE" "$STAGING/BendyFree.app"
ln -s /Applications "$STAGING/Applications"
rm -f -- "$DMG"
hdiutil create -volname "BendyFree" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf -- "$STAGING"
echo "Created $DMG ($(du -h "$DMG" | cut -f1))"
