#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="$PROJECT_DIR/dist/CatPomodoro.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$PROJECT_DIR/.build/AppIcon.iconset"

swift build --package-path "$PROJECT_DIR" -c release
BIN_DIR="$(swift build --package-path "$PROJECT_DIR" -c release --show-bin-path)"

if [[ -d "$APP_DIR" ]]; then
    rm -rf "$APP_DIR"
fi

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_DIR/CatPomodoro" "$MACOS_DIR/CatPomodoro"
cp "$PROJECT_DIR/Config/Info.plist" "$CONTENTS_DIR/Info.plist"

cp "$PROJECT_DIR/Sources/CatPomodoro/Resources/cat_timer_frame.png" "$RESOURCES_DIR/cat_timer_frame.png"
cp "$PROJECT_DIR/Sources/CatPomodoro/Resources/cat_timer_body.png" "$RESOURCES_DIR/cat_timer_body.png"
cp "$PROJECT_DIR/Sources/CatPomodoro/Resources/cat_tail.png" "$RESOURCES_DIR/cat_tail.png"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
ICON_SOURCE="$PROJECT_DIR/Assets/AppIconSource.png"

sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "$APP_DIR"
