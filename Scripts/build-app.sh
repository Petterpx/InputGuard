#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="DoubaoVoiceRestore"
OUT_DIR="build"
APP="$OUT_DIR/$APP_NAME.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

IDENTITY="${CODE_SIGN_IDENTITY:--}"
codesign --force --sign "$IDENTITY" --identifier "dev.petterp.DoubaoVoiceRestore" "$APP"
codesign --verify --verbose=2 "$APP"
echo "built: $APP"
