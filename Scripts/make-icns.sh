#!/bin/bash
# 用系统 SF Symbol 渲染应用图标并生成 Resources/AppIcon.icns（方案 D：系统蓝 + 键盘 + 回转箭头）
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
swiftc -O Scripts/render-app-icon.swift -o "$TMP/render"
ICONSET="$TMP/AppIcon.iconset"; mkdir -p "$ICONSET"
# 16 / 32 太小，箭头会糊成一团，按小尺寸简化惯例只画键盘
for px in 16 32; do
  "$TMP/render" "$TMP/icon_$px.png" "$px" 3D8BFF 0A5BD6 keyboard.fill >/dev/null
done
for px in 64 128 256 512 1024; do
  "$TMP/render" "$TMP/icon_$px.png" "$px" 3D8BFF 0A5BD6 keyboard.fill arrow.uturn.backward >/dev/null
done
cp "$TMP/icon_16.png"   "$ICONSET/icon_16x16.png";      cp "$TMP/icon_32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$TMP/icon_32.png"   "$ICONSET/icon_32x32.png";      cp "$TMP/icon_64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$TMP/icon_128.png"  "$ICONSET/icon_128x128.png";    cp "$TMP/icon_256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$TMP/icon_256.png"  "$ICONSET/icon_256x256.png";    cp "$TMP/icon_512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$TMP/icon_512.png"  "$ICONSET/icon_512x512.png";    cp "$TMP/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "built: Resources/AppIcon.icns"
