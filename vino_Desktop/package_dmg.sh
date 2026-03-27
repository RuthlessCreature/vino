#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build_cmake"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$DIST_DIR/vino_Desktop"
APP_NAME="vino_Desktop.app"
APP_PATH="$BUILD_DIR/$APP_NAME"
DMG_PATH="$DIST_DIR/vino_Desktop-0.1.0.dmg"
CMAKE_BIN="${CMAKE_BIN:-/Applications/CMake.app/Contents/bin/cmake}"

echo "[vino_Desktop] 生成图标资源"
python3 "$ROOT_DIR/Resources/generate_icon_assets.py"
/usr/bin/iconutil -c icns "$ROOT_DIR/Resources/AppIcon.iconset" -o "$ROOT_DIR/Resources/vino_Desktop.icns"

echo "[vino_Desktop] 配置并编译"
"$CMAKE_BIN" -S "$ROOT_DIR" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release
"$CMAKE_BIN" --build "$BUILD_DIR" --parallel 6

echo "[vino_Desktop] 准备 DMG 暂存目录"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -sfn /Applications "$STAGE_DIR/Applications"

echo "[vino_Desktop] 生成 DMG"
mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
/usr/bin/hdiutil create \
  -volname "vino Desktop" \
  -srcfolder "$STAGE_DIR" \
  -format UDZO \
  "$DMG_PATH"

echo "[vino_Desktop] 完成: $DMG_PATH"
