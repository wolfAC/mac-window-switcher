#!/bin/sh
# Builds a universal (Intel + Apple Silicon) release and wraps it in build/Window Switcher.app.
# Signs with $SIGN_IDENTITY if set (a self-signed cert keeps permissions across updates), else ad-hoc.
set -e
cd "$(dirname "$0")/.."

# Use the local self-signed "Window Switcher Dev" certificate when there is one, so the
# signature (and with it the user's permissions) stays the same across builds.
if [ -z "$SIGN_IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -q '"Window Switcher Dev"'; then
    SIGN_IDENTITY="Window Switcher Dev"
fi

# Multi-arch `swift build` needs full Xcode, so build each arch and merge with lipo.
for ARCH in arm64 x86_64; do
    swift build -c release --arch "$ARCH"
done
ARM="$(swift build -c release --arch arm64 --show-bin-path)/WindowSwitcher"
X86="$(swift build -c release --arch x86_64 --show-bin-path)/WindowSwitcher"

APP="build/Window Switcher.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
lipo -create "$ARM" "$X86" -output "$APP/Contents/MacOS/WindowSwitcher"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
    mkdir -p "$APP/Contents/Resources"
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
