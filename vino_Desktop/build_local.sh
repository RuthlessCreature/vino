#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build_cmake"

if [ "${CMAKE_BIN:-}" = "" ]; then
  if command -v cmake >/dev/null 2>&1; then
    CMAKE_BIN="$(command -v cmake)"
  elif [ -x /Applications/CMake.app/Contents/bin/cmake ]; then
    CMAKE_BIN="/Applications/CMake.app/Contents/bin/cmake"
  else
    echo "cmake not found; set CMAKE_BIN manually" >&2
    exit 1
  fi
fi

if [ "${BUILD_PARALLEL:-}" = "" ]; then
  BUILD_PARALLEL="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
fi

"$CMAKE_BIN" -S "$ROOT_DIR" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-Debug}"
"$CMAKE_BIN" --build "$BUILD_DIR" --parallel "$BUILD_PARALLEL"

echo "built: $BUILD_DIR/vino_desktop_blueprint"
if [ -f "$BUILD_DIR/vino_desktop_app" ]; then
  echo "built: $BUILD_DIR/vino_desktop_app"
fi
