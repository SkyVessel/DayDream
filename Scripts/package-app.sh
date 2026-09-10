#!/bin/bash
# Build a signed DayDream.app without opening it.
set -e
cd "$(dirname "$0")/.."

SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
HARDENED_RUNTIME="${HARDENED_RUNTIME:-0}"

swift build -c release

APP="DayDream.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DayDream "$APP/Contents/MacOS/"
cp Scripts/Info.plist "$APP/Contents/"

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
trap 'rm -rf "${ICONSET%/AppIcon.iconset}"' EXIT

sips -z 16 16 Assets/AppIcon.png --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 Assets/AppIcon.png --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 Assets/AppIcon.png --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 Assets/AppIcon.png --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 Assets/AppIcon.png --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 Assets/AppIcon.png --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 Assets/AppIcon.png --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 Assets/AppIcon.png --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 Assets/AppIcon.png --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 Assets/AppIcon.png --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    CODE_SIGN_ARGS=(--force --sign "$SIGNING_IDENTITY")
    if [[ "$HARDENED_RUNTIME" == "1" ]]; then
        CODE_SIGN_ARGS+=(--options runtime --timestamp)
    fi
    codesign "${CODE_SIGN_ARGS[@]}" "$APP"
else
    codesign --force --sign - "$APP"
fi

codesign --verify --deep --strict "$APP"

if [[ "${1:-}" != "--no-launch" ]]; then
    open "$APP"
fi
