#!/bin/bash
# mac/ の Swift Package を release ビルドし、LSUIElement=true の .app バンドルに詰める。
# Xcode プロジェクトなし・ad-hoc 署名のみ・公証なし。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MornUsageBar"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_DIR/Contents/Info.plist"

codesign --force --deep --sign - "$APP_DIR"

echo "Built: $APP_DIR"
