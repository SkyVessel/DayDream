#!/bin/bash
# 打包并启动 DayDream.app（无需打开 Xcode）
set -e
cd "$(dirname "$0")/.."

swift build -c release

APP="DayDream.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/DayDream "$APP/Contents/MacOS/"
cp Scripts/Info.plist "$APP/Contents/"

open "$APP"
