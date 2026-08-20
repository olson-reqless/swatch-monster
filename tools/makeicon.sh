#!/bin/zsh
# Renders Resources/AppIcon.icns from tools/makeicon.swift.
# To use your own artwork instead, drop a 1024x1024 PNG at tools/icon-source.png.
set -euo pipefail
cd "${0:A:h}/.."

mkdir -p Resources
SRC="tools/icon-source.png"

if [[ ! -f "$SRC" ]]; then
    echo "==> Rendering placeholder icon"
    swift tools/makeicon.swift "$SRC"
fi

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
    px="${spec%% *}"
    name="${spec##* }"
    sips -z "$px" "$px" "$SRC" --out "$ICONSET/icon_${name}.png" >/dev/null 2>&1
done

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
rm -rf "$ICONSET"
echo "==> Wrote Resources/AppIcon.icns"
