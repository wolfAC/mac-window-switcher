#!/bin/sh
# Packages build/Window Switcher.app into build/WindowSwitcher.dmg with an Applications shortcut.
# Run scripts/build-app.sh first.
set -e
cd "$(dirname "$0")/.."

APP="build/Window Switcher.app"
[ -d "$APP" ] || { echo "Missing $APP — run scripts/build-app.sh first" >&2; exit 1; }

STAGING="build/dmg"
DMG="build/WindowSwitcher.dmg"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Window Switcher" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
echo "Built $DMG"
