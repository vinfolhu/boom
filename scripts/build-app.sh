#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

swift build -c release
swift build \
    -c release \
    --triple arm64-apple-macosx13.0 \
    --build-path "$PROJECT_DIR/.build-arm64"

APP_DIR="$PROJECT_DIR/dist/BoomPet.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
lipo -create \
    "$PROJECT_DIR/.build/release/BoomPet" \
    "$PROJECT_DIR/.build-arm64/arm64-apple-macosx/release/BoomPet" \
    -output "$MACOS_DIR/BoomPet"
cp "$PROJECT_DIR/Sources/BoomPet/Resources/pet.png" "$RESOURCES_DIR/pet.png"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
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
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

chmod +x "$MACOS_DIR/BoomPet"
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
