#!/bin/bash
# tools/make-icon.swift で 1024px PNG を描画し、iconutil で Resources/AppIcon.icns を生成する。
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="build"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
SOURCE_PNG="$BUILD_DIR/AppIcon-1024.png"

mkdir -p "$BUILD_DIR"
swift tools/make-icon.swift "$SOURCE_PNG" 1024

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

declare -a SIZES=(16 32 32 64 128 256 256 512 512 1024)
declare -a NAMES=(
    icon_16x16.png
    icon_16x16@2x.png
    icon_32x32.png
    icon_32x32@2x.png
    icon_128x128.png
    icon_128x128@2x.png
    icon_256x256.png
    icon_256x256@2x.png
    icon_512x512.png
    icon_512x512@2x.png
)

for i in "${!SIZES[@]}"; do
    sips -z "${SIZES[$i]}" "${SIZES[$i]}" "$SOURCE_PNG" --out "$ICONSET_DIR/${NAMES[$i]}" >/dev/null
done

mkdir -p Resources
iconutil -c icns "$ICONSET_DIR" -o Resources/AppIcon.icns

echo "Built: Resources/AppIcon.icns"
echo "Source PNG: $SOURCE_PNG"
