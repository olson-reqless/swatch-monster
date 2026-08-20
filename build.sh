#!/bin/zsh
# Builds Swatch Monster.app from source using only the Command Line Tools.
# Usage: ./build.sh          build into ./build
#        ./build.sh install  build, then install to /Applications and relaunch

set -euo pipefail
cd "${0:A:h}"

APP_NAME="Swatch Monster"
EXEC_NAME="SwatchMonster"
BUNDLE_ID="com.shawnolson.swatchmonster"
VERSION="1.0"
MIN_MACOS="14.0"

BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> Building $APP_NAME $VERSION"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Native arm64. Add -target x86_64-apple-macos14.0 and lipo if you ever need
# a universal build, but this machine is Apple Silicon.
swiftc \
  -O \
  -parse-as-library \
  -target "arm64-apple-macos${MIN_MACOS}" \
  -framework AppKit \
  -framework SwiftUI \
  -framework ServiceManagement \
  -framework ScreenCaptureKit \
  -framework Carbon \
  -o "$APP/Contents/MacOS/$EXEC_NAME" \
  Sources/*.swift

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$EXEC_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSHumanReadableCopyright</key><string>Shawn Olson</string>
</dict>
</plist>
PLIST

# Everything in Resources/ ships inside the bundle (icon, color-name list,
# third-party licences).
if [[ -d Resources ]]; then
    cp -R Resources/. "$APP/Contents/Resources/"
fi

# Ad-hoc signature. Enough to run locally and to keep the login item stable;
# not notarized, so this build is for your machine, not for handing out.
codesign --force --sign - "$APP" >/dev/null 2>&1

echo "==> Built $APP"

if [[ "${1:-}" == "install" ]]; then
    echo "==> Installing to /Applications"
    pkill -x "$EXEC_NAME" 2>/dev/null || true
    sleep 1
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app"
    echo "==> Running. Look for the eyedropper in your menu bar."
fi
