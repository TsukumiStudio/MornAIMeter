#!/bin/bash
# mac/ の Swift Package を release ビルドし、LSUIElement=true の .app バンドルに詰める。
# Xcode プロジェクトなし・ad-hoc 署名のみ・公証なし。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MornAIMeter"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
VERSION="${VERSION:-0.0.0}"

swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$APP_DIR/Contents/Info.plist"

mkdir -p "$APP_DIR/Contents/Resources"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP_DIR"

echo "Built: $APP_DIR"
