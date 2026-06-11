#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SilentMode"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_DIR="$ROOT_DIR/dist/archives"
EXPORT_DIR="$ROOT_DIR/dist/developer-id"
EXPORT_OPTIONS="$ROOT_DIR/Xcode/ExportOptions/DeveloperID.plist"
ARCHIVE_PATH="$ARCHIVE_DIR/$APP_NAME.xcarchive"
APP_BUNDLE="$EXPORT_DIR/$APP_NAME.app"

mkdir -p "$ARCHIVE_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"

xcodebuild \
  -project "$ROOT_DIR/SilentMode.xcodeproj" \
  -scheme SilentMode \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

if [ ! -d "$APP_BUNDLE" ]; then
  echo "Expected exported app at $APP_BUNDLE" >&2
  exit 1
fi

if [ -n "${DEVELOPER_ID_APPLICATION:-}" ]; then
  CONTROL_EXTENSION="$APP_BUNDLE/Contents/PlugIns/SilentModeControlExtension.appex"
  if [ -d "$CONTROL_EXTENSION" ]; then
    codesign \
      --force \
      --options runtime \
      --timestamp \
      --sign "$DEVELOPER_ID_APPLICATION" \
      --entitlements "$ROOT_DIR/Xcode/Entitlements/SilentModeControl.entitlements" \
      "$CONTROL_EXTENSION"
  fi

  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$DEVELOPER_ID_APPLICATION" \
    --entitlements "$ROOT_DIR/Xcode/Entitlements/SilentMode.entitlements" \
    "$APP_BUNDLE"
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_BUNDLE/Contents/Info.plist")"
DMG_PATH="$ROOT_DIR/dist/$APP_NAME-$VERSION-$BUILD.dmg"

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$APP_BUNDLE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [ -n "${DEVELOPER_ID_APPLICATION:-}" ]; then
  codesign --force --sign "$DEVELOPER_ID_APPLICATION" "$DMG_PATH"
fi

if [ -n "${NOTARYTOOL_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
else
  echo "Skipping notarization because NOTARYTOOL_PROFILE is not set."
  echo "After storing credentials with notarytool, rerun with NOTARYTOOL_PROFILE=<profile-name>."
fi

echo "Built $DMG_PATH"
