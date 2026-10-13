#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${WOOF_TESTFLIGHT_OUTPUT_DIR:-$IOS_DIR/build/testflight}"
BUILD_NUMBER="${WOOF_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
ARCHIVE_PATH="$OUTPUT_DIR/WooF.Play-$BUILD_NUMBER.xcarchive"

/bin/mkdir -p "$OUTPUT_DIR"

/usr/bin/xcodebuild archive \
    -project "$IOS_DIR/KinoPad.xcodeproj" \
    -scheme KinoPad \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

echo "Архив готов: $ARCHIVE_PATH"
echo "Откройте Xcode → Window → Organizer → Archives и выберите Distribute App → App Store Connect → Upload."
