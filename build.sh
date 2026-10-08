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

# Build against the SDK matching the running macOS. A Command Line Tools update
# can make a newer beta SDK the default, and the 27.0 one ships without the
# SwiftUI macro plugin, so @State fails to compile against it.
if [[ -z "${SDKROOT:-}" ]]; then
    OS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
    MATCHING_SDK="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX${OS_MAJOR}.*.sdk 2>/dev/null | sort -V | tail -1)"
    [[ -n "$MATCHING_SDK" ]] && export SDKROOT="$MATCHING_SDK"
fi

echo "==> Building $APP_NAME $VERSION${SDKROOT:+ (SDK: ${SDKROOT:t})}"

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

# Sign with a stable local identity if one exists. This matters for more than
# tidiness: an ad-hoc signature is derived from the binary itself, so every
# rebuild looks like a different app to macOS and Screen Recording permission is
# revoked — which silently disables the zoom loupe. A certificate keeps the
# identity constant across rebuilds, so the permission granted once sticks.
#
# Create the certificate with tools/make-signing-cert.sh. Still not notarized:
# this build is for this machine, not for distribution.
SIGN_IDENTITY="Swatch Monster Local Signing"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    codesign --force --sign "$SIGN_IDENTITY" "$APP" >/dev/null 2>&1
    echo "==> Signed as \"$SIGN_IDENTITY\""
else
    codesign --force --sign - "$APP" >/dev/null 2>&1
    echo "==> Signed ad-hoc (no \"$SIGN_IDENTITY\" identity found)"
    echo "    Screen Recording permission will reset on each rebuild."
fi

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
