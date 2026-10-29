#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONFIG="${1:-release}"
echo "==> Building Pata Native macOS App with Swift ($CONFIG mode)..."

XCODE_PLUGIN_DIR="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"
CLT_PLUGIN_DIR="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"

SWIFT_FLAGS=()
if [ -d "$XCODE_PLUGIN_DIR" ]; then
    SWIFT_FLAGS+=("-Xswiftc" "-plugin-path" "-Xswiftc" "$XCODE_PLUGIN_DIR")
fi
if [ -d "$CLT_PLUGIN_DIR" ]; then
    SWIFT_FLAGS+=("-Xswiftc" "-plugin-path" "-Xswiftc" "$CLT_PLUGIN_DIR")
fi

if [ "$CONFIG" = "release" ] || [ "$CONFIG" = "--release" ]; then
    swift build -c release "${SWIFT_FLAGS[@]}"
    BIN_PATH="$(find .build -path "*Release/Pata" -type f -perm +111 | head -n 1)"
else
    swift build "${SWIFT_FLAGS[@]}"
    BIN_PATH="$(find .build -path "*Debug/Pata" -type f -perm +111 | head -n 1)"
fi

if [ -z "$BIN_PATH" ]; then
    echo "Error: Pata binary not found after build!"
    exit 1
fi

APP_DIR="build/bin/Pata.app"
echo "==> Creating macOS App Bundle at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/pata"
chmod +x "$APP_DIR/Contents/MacOS/pata"

if [ "$CONFIG" = "release" ] || [ "$CONFIG" = "--release" ]; then
    strip -rSTx "$APP_DIR/Contents/MacOS/pata" 2>/dev/null || true
fi

if [ -f "build/darwin/icons.icns" ]; then
    cp "build/darwin/icons.icns" "$APP_DIR/Contents/Resources/icons.icns"
fi

if [ -f "build/darwin/Info.plist" ]; then
    cp "build/darwin/Info.plist" "$APP_DIR/Contents/Info.plist"
fi

echo "==> Ad-hoc signing App Bundle..."
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo "==> Done! App bundle successfully built at $APP_DIR ($(du -sh "$APP_DIR" | cut -f1))"
