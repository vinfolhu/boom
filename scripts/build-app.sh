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

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
lipo -create \
    "$X86_BUILD_DIR/x86_64-apple-macosx/release/BoomPet" \
    "$ARM_BUILD_DIR/arm64-apple-macosx/release/BoomPet" \
    -output "$MACOS_DIR/BoomPet"
cp "$PROJECT_DIR/Sources/BoomPet/Resources/pet.png" "$RESOURCES_DIR/pet.png"
for PET_PART in body head ear-left ear-right eyes mouth paws tail; do
    cp \
        "$PROJECT_DIR/Sources/BoomPet/Resources/pet-$PET_PART.png" \
        "$RESOURCES_DIR/pet-$PET_PART.png"
done

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
    <string>com.local.BoomPet</string>
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
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
