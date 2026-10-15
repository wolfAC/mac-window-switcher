#!/bin/sh
# Fast iteration: debug build for this Mac's arch, wrap it in build/Window Switcher.app, relaunch.
# Ad-hoc signing changes the signature on every build, so macOS forgets the permissions.
# Set SIGN_IDENTITY to a self-signed certificate to keep them (see README).
set -e
cd "$(dirname "$0")/.."

swift build
BIN="$(swift build --show-bin-path)/WindowSwitcher"

APP="build/Window Switcher.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/WindowSwitcher"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"

pkill -x WindowSwitcher 2>/dev/null || true
sleep 0.3
open "$APP"
echo "Relaunched $APP (logs: log stream --predicate 'subsystem == \"com.wolf.windowswitcher\"')"
