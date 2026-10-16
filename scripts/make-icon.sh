#!/bin/sh
# Makes Resources/AppIcon.icns from one 1024×1024 PNG: scripts/make-icon.sh icon.png
# The app's own icon comes from scripts/draw-icon.swift:
#   swift scripts/draw-icon.swift build/AppIcon.png && scripts/make-icon.sh build/AppIcon.png
set -e
cd "$(dirname "$0")/.."
SRC="${1:?usage: scripts/make-icon.sh path/to/icon-1024.png}"

SET="build/AppIcon.iconset"
rm -rf "$SET"
mkdir -p "$SET"
for SIZE in 16 32 128 256 512; do
    sips -z $SIZE $SIZE "$SRC" --out "$SET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z $DOUBLE $DOUBLE "$SRC" --out "$SET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
rm -rf "$SET"
echo "Wrote Resources/AppIcon.icns"
