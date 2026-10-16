#!/bin/sh
# Publishes a GitHub release built and signed on this Mac, so the signing key never leaves it.
#   scripts/release.sh 0.2.0
# Sets the version in Info.plist, commits, tags v<version>, builds the universal app,
# makes the zip + DMG, pushes, and uploads them with `gh release create`.
set -e
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version, e.g. 0.2.0>}"
TAG="v$VERSION"
IDENTITY="${SIGN_IDENTITY:-Window Switcher Dev}"

# Releases must be signed with the same certificate every time, or users lose their permissions.
if ! security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
    echo "Signing certificate \"$IDENTITY\" not found in the keychain; refusing to publish an ad-hoc build." >&2
    exit 1
fi
if [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then
    echo "Release from main." >&2
    exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
    echo "Working tree has uncommitted changes; commit or stash them first." >&2
    exit 1
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "Tag $TAG already exists." >&2
    exit 1
fi

swift test

# Version: marketing version from the argument, build number = commit count (always increasing).
BUILD_NUMBER=$(($(git rev-list --count HEAD) + 1))
plutil -replace CFBundleShortVersionString -string "$VERSION" Resources/Info.plist
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" Resources/Info.plist
if [ -n "$(git status --porcelain Resources/Info.plist)" ]; then
    git add Resources/Info.plist
    git commit -q -m "Release $TAG"
fi
git tag -a "$TAG" -m "Window Switcher $VERSION"

SIGN_IDENTITY="$IDENTITY" ./scripts/build-app.sh
./scripts/make-dmg.sh
rm -f build/WindowSwitcher.zip
ditto -c -k --keepParent "build/Window Switcher.app" build/WindowSwitcher.zip

git push origin main "$TAG"
gh release create "$TAG" build/WindowSwitcher.dmg build/WindowSwitcher.zip \
    --title "Window Switcher $VERSION" \
    --generate-notes

echo
echo "Released $TAG."
echo "Homebrew cask: version \"$VERSION\", sha256 \"$(shasum -a 256 build/WindowSwitcher.zip | cut -d' ' -f1)\""
