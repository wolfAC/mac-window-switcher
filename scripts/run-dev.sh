#!/bin/sh
# Fast iteration: debug build for this Mac's arch, wrap it in build/Window Switcher.app, relaunch.
# Without a stable certificate, ad-hoc signing changes the signature on every build and
# macOS forgets the permissions (see README).
set -e
cd "$(dirname "$0")/.."

# Use the local self-signed "Window Switcher Dev" certificate when there is one, so the
# signature (and with it the user's permissions) stays the same across builds.
if [ -z "$SIGN_IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -q '"Window Switcher Dev"'; then
    SIGN_IDENTITY="Window Switcher Dev"
fi

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
