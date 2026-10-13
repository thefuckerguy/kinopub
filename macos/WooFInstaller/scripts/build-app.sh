#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPOSITORY_DIR="$(cd "$PACKAGE_DIR/../.." && pwd)"
OUTPUT_DIR="$PACKAGE_DIR/build"
OUTPUT_APP="$OUTPUT_DIR/WooF Installer.app"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/woof-installer-app.XXXXXX")"
TEMP_APP="$TEMP_ROOT/WooF Installer.app"

cleanup() {
    /bin/rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

/usr/bin/swift build --package-path "$PACKAGE_DIR" --configuration release
BIN_DIR="$(/usr/bin/swift build --package-path "$PACKAGE_DIR" --configuration release --show-bin-path)"

/bin/mkdir -p "$TEMP_APP/Contents/MacOS" "$TEMP_APP/Contents/Resources" "$OUTPUT_DIR"
/usr/bin/ditto "$BIN_DIR/WooFInstaller" "$TEMP_APP/Contents/MacOS/WooFInstaller"
/usr/bin/ditto "$PACKAGE_DIR/Resources/Info.plist" "$TEMP_APP/Contents/Info.plist"

ICON_SOURCE="$REPOSITORY_DIR/ios/KinoPad/Resources/Assets.xcassets/WooFMascot.imageset/WooFMascot.png"
if [[ -f "$ICON_SOURCE" ]]; then
    ICONSET="$TEMP_ROOT/AppIcon.iconset"
    /bin/mkdir -p "$ICONSET"
    /usr/bin/sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
    /usr/bin/sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
    /usr/bin/sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
    /usr/bin/sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
    /usr/bin/sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
    /usr/bin/sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    /usr/bin/sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
    /usr/bin/sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    /usr/bin/sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
    /usr/bin/sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
    /usr/bin/iconutil -c icns "$ICONSET" -o "$TEMP_APP/Contents/Resources/AppIcon.icns"
fi

/usr/bin/codesign --force --deep --sign - "$TEMP_APP"
/usr/bin/ditto "$TEMP_APP" "$OUTPUT_APP"
/usr/bin/codesign --verify --deep --strict "$OUTPUT_APP"

echo "Готово: $OUTPUT_APP"
