#!/bin/bash
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${JEV_OUTPUT_DIR:-$SOURCE_DIR/dist}"
APP_NAME="${JEV_APP_NAME:-Jev Voice}"
BUNDLE_ID="${JEV_BUNDLE_ID:-ai.jevvoice.public}"
ARCH="${JEV_ARCH:-arm64}"
APP="$OUTPUT_DIR/$APP_NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -swift-version 5 -target "$ARCH-apple-macos14.0" -O -parse-as-library \
  -framework AppKit -framework SwiftUI -framework Speech -framework AVFoundation \
  -framework ApplicationServices -framework Security -framework LocalAuthentication -framework Carbon \
  "$SOURCE_DIR"/Sources/*.swift -o "$APP/Contents/MacOS/JevVoice"
cp "$SOURCE_DIR/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$APP/Contents/Info.plist"
if [ -d "$SOURCE_DIR/Localizations" ]; then cp -R "$SOURCE_DIR/Localizations"/*.lproj "$APP/Contents/Resources/"; fi
if [ -f "$SOURCE_DIR/AppIcon.icns" ]; then cp "$SOURCE_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"; fi

if [ -n "${JEV_SIGNING_IDENTITY:-}" ]; then
  codesign --force --sign "$JEV_SIGNING_IDENTITY" --timestamp --identifier "$BUNDLE_ID" \
    --entitlements "$SOURCE_DIR/Entitlements.plist" "$APP"
fi

printf 'Built %s\n' "$APP"
