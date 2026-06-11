#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="SilentMode"
BUNDLE_ID="com.josh.silentmode"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/xcode"
BUILT_APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
INSTALLED_APP_BUNDLE="/Applications/$APP_NAME.app"
APP_BINARY="$INSTALLED_APP_BUNDLE/Contents/MacOS/$APP_NAME"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x "SilentModeControlExtension" >/dev/null 2>&1 || true

xcodebuild \
  -project "$ROOT_DIR/SilentMode.xcodeproj" \
  -scheme SilentMode \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  build

if [ -e "$INSTALLED_APP_BUNDLE" ]; then
  "$LSREGISTER" -u "$INSTALLED_APP_BUNDLE" >/dev/null 2>&1 || true
  if [ -e "$INSTALLED_APP_BUNDLE/Contents/PlugIns/SilentModeControlExtension.appex" ]; then
    "$LSREGISTER" -u "$INSTALLED_APP_BUNDLE/Contents/PlugIns/SilentModeControlExtension.appex" >/dev/null 2>&1 || true
  fi
  rm -rf "$INSTALLED_APP_BUNDLE"
fi

/usr/bin/ditto "$BUILT_APP_BUNDLE" "$INSTALLED_APP_BUNDLE"

for stale_bundle in \
  "$ROOT_DIR/dist/$APP_NAME.app" \
  "$ROOT_DIR/.build/signed-auto/Build/Products/Debug/$APP_NAME.app" \
  "$BUILT_APP_BUNDLE"
do
  if [ -e "$stale_bundle" ]; then
    "$LSREGISTER" -u "$stale_bundle" >/dev/null 2>&1 || true
    if [ -e "$stale_bundle/Contents/PlugIns/SilentModeControlExtension.appex" ]; then
      "$LSREGISTER" -u "$stale_bundle/Contents/PlugIns/SilentModeControlExtension.appex" >/dev/null 2>&1 || true
    fi
  fi
done

"$LSREGISTER" -f -R -trusted "$INSTALLED_APP_BUNDLE"
killall ControlCenter >/dev/null 2>&1 || true
killall Dock >/dev/null 2>&1 || true

open_app() {
  /usr/bin/open "$INSTALLED_APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
