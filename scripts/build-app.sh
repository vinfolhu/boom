#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

BOOMPET_VERSION="${BOOMPET_VERSION:-$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")}"
BOOMPET_BUILD_NUMBER="${BOOMPET_BUILD_NUMBER:-1}"
X86_BUILD_DIR="$PROJECT_DIR/.build-x86_64"
ARM_BUILD_DIR="$PROJECT_DIR/.build-arm64"

swift build \
    -c release \
    --triple x86_64-apple-macosx13.0 \
    --build-path "$X86_BUILD_DIR"
swift build \
    -c release \
    --triple arm64-apple-macosx13.0 \
    --build-path "$ARM_BUILD_DIR"

APP_DIR="$PROJECT_DIR/dist/BoomPet.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

if [[ "$APP_DIR" != "$PROJECT_DIR/dist/BoomPet.app" ]]; then
    echo "Refusing to clean unexpected app path: $APP_DIR" >&2
    exit 1
fi
rm -rf -- "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
lipo -create \
    "$X86_BUILD_DIR/x86_64-apple-macosx/release/BoomPet" \
    "$ARM_BUILD_DIR/arm64-apple-macosx/release/BoomPet" \
    -output "$MACOS_DIR/BoomPet"
strip -x "$MACOS_DIR/BoomPet"
RIG_RESOURCES_DIR="$RESOURCES_DIR/DefaultPetRig"
mkdir -p "$RIG_RESOURCES_DIR"
cp \
    "$PROJECT_DIR/Sources/BoomPet/Resources/DefaultPetRig/pet-rig.json" \
    "$RIG_RESOURCES_DIR/pet-rig.json"
for RIG_PART in \
    body head ear-left ear-right eyes mouth shadow tail \
    leg-front-left leg-front-right leg-rear-left leg-rear-right; do
    cp \
        "$PROJECT_DIR/Sources/BoomPet/Resources/DefaultPetRig/$RIG_PART.png" \
        "$RIG_RESOURCES_DIR/$RIG_PART.png"
done

ICON_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/boompet-icon.XXXXXX")"
cleanup_icon_temp() {
    if [[ "$ICON_TEMP_DIR" == */boompet-icon.* && -d "$ICON_TEMP_DIR" ]]; then
        rm -rf -- "$ICON_TEMP_DIR"
    fi
}
trap cleanup_icon_temp EXIT

case "$(uname -m)" in
    arm64)
        ICON_RENDERER="$ARM_BUILD_DIR/arm64-apple-macosx/release/BoomPet"
        ;;
    *)
        ICON_RENDERER="$X86_BUILD_DIR/x86_64-apple-macosx/release/BoomPet"
        ;;
esac

ICON_SOURCE="$ICON_TEMP_DIR/icon-1024.png"
ICONSET_DIR="$ICON_TEMP_DIR/BoomPet.iconset"
mkdir -p "$ICONSET_DIR"
"$ICON_RENDERER" --render-app-icon "$ICON_SOURCE"
for ICON_SIZE in 16 32 128 256 512; do
    sips -z "$ICON_SIZE" "$ICON_SIZE" "$ICON_SOURCE" \
        --out "$ICONSET_DIR/icon_${ICON_SIZE}x${ICON_SIZE}.png" >/dev/null
    DOUBLE_SIZE=$((ICON_SIZE * 2))
    sips -z "$DOUBLE_SIZE" "$DOUBLE_SIZE" "$ICON_SOURCE" \
        --out "$ICONSET_DIR/icon_${ICON_SIZE}x${ICON_SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/BoomPet.icns"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>BoomPet</string>
    <key>CFBundleExecutable</key>
    <string>BoomPet</string>
    <key>CFBundleIdentifier</key>
    <string>com.vinfol.boom</string>
    <key>CFBundleIconFile</key>
    <string>BoomPet.icns</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>BoomPet</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$BOOMPET_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BOOMPET_BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>BoomPet uses screen capture only for user-selected OCR and sticky-image regions.</string>
</dict>
</plist>
PLIST

chmod +x "$MACOS_DIR/BoomPet"
if [[ -n "${BOOMPET_CODESIGN_IDENTITY:-}" ]]; then
    codesign \
        --force \
        --deep \
        --options runtime \
        --timestamp \
        --sign "$BOOMPET_CODESIGN_IDENTITY" \
        "$APP_DIR"
else
    codesign --force --deep --sign - "$APP_DIR"
fi
echo "$APP_DIR"
