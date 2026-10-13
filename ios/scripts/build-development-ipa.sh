#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
IOS_DIR="${SCRIPT_DIR:h}"
BUILD_ROOT="$IOS_DIR/build/installer"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
PACKAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/woofplay-ipa.XXXXXX")"

cleanup() {
  /bin/rm -rf "$PACKAGE_ROOT"
}
trap cleanup EXIT

xcodebuild \
  -project "$IOS_DIR/KinoPad.xcodeproj" \
  -scheme KinoPad \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Release-iphoneos/KinoPad.app"
if [[ ! -d "$APP_PATH" ]]; then
  print -u2 "Не найдена собранная программа: $APP_PATH"
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Info.plist")
OUTPUT_PATH="$BUILD_ROOT/WooF.Play-$VERSION-development.ipa"

mkdir -p "$PACKAGE_ROOT/Payload" "$BUILD_ROOT"
/usr/bin/ditto "$APP_PATH" "$PACKAGE_ROOT/Payload/KinoPad.app"
/usr/bin/ditto -c -k --norsrc "$PACKAGE_ROOT" "$OUTPUT_PATH"

print "Готово: $OUTPUT_PATH"
print "Пакет подписан для development-устройств из профиля Xcode. Для других устройств используйте TestFlight или сначала зарегистрируйте их в Xcode."
