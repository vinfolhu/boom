#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

RELEASE_VERSION="${BOOMPET_VERSION:-$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")}"
if [[ ! "$RELEASE_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "Invalid VERSION: $RELEASE_VERSION" >&2
    exit 1
fi

export BOOMPET_VERSION="$RELEASE_VERSION"
"$PROJECT_DIR/scripts/build-app.sh"

APP_PATH="$PROJECT_DIR/dist/BoomPet.app"
ZIP_PATH="$PROJECT_DIR/dist/BoomPet-macOS-universal.zip"
DMG_PATH="$PROJECT_DIR/dist/BoomPet-macOS-universal.dmg"
ZIP_CHECKSUM_PATH="$ZIP_PATH.sha256"
DMG_CHECKSUM_PATH="$DMG_PATH.sha256"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Missing application bundle: $APP_PATH" >&2
    exit 1
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/boompet-release.XXXXXX")"
cleanup() {
    if [[ "$STAGING_DIR" == */boompet-release.* && -d "$STAGING_DIR" ]]; then
        rm -rf -- "$STAGING_DIR"
    fi
}
trap cleanup EXIT

cp -R "$APP_PATH" "$STAGING_DIR/BoomPet.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$ZIP_PATH" "$DMG_PATH" "$ZIP_CHECKSUM_PATH" "$DMG_CHECKSUM_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
hdiutil create \
    -volname "BoomPet $RELEASE_VERSION" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -ov \
    "$DMG_PATH"

shasum -a 256 "$ZIP_PATH" > "$ZIP_CHECKSUM_PATH"
shasum -a 256 "$DMG_PATH" > "$DMG_CHECKSUM_PATH"

echo "Release $RELEASE_VERSION is ready:"
echo "  $DMG_PATH"
echo "  $ZIP_PATH"
echo "  $DMG_CHECKSUM_PATH"
echo "  $ZIP_CHECKSUM_PATH"
