#!/bin/bash
# 把 build/DoubaoVoiceRestore.app 打成 build/DoubaoVoiceRestore-<版本>.dmg，
# 镜像里带「应用程序」快捷方式，拖过去即安装。
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="DoubaoVoiceRestore"
APP="build/$APP_NAME.app"
[ -d "$APP" ] || { echo "先跑 Scripts/build-app.sh" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/$APP_NAME-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/应用程序"

rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
echo "built: $DMG"
