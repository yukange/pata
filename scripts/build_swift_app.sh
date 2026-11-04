#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONFIG="${1:-release}"
SIGNING_IDENTITY="${PATA_SIGNING_IDENTITY:--}"
if [ "$SIGNING_IDENTITY" != "-" ] && ! security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
    echo "Error: signing identity '$SIGNING_IDENTITY' not found. Set PATA_SIGNING_IDENTITY to an available certificate name."
    exit 1
fi
echo "==> Building Pata Native macOS App with Swift ($CONFIG mode)..."

DEV_DIR="$(xcode-select -p 2>/dev/null || echo "")"
SWIFT_FLAGS=()
for p in \
    "$DEV_DIR/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins" \
    "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins" \
    "$DEV_DIR/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing" \
    "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"; do
    if [ -d "$p" ]; then
        SWIFT_FLAGS+=("-Xswiftc" "-plugin-path" "-Xswiftc" "$p")
    fi
done

if [ "$CONFIG" = "release" ] || [ "$CONFIG" = "--release" ]; then
    BUILD_CONFIGURATION="release"
else
    BUILD_CONFIGURATION="debug"
fi
swift build -c "$BUILD_CONFIGURATION" "${SWIFT_FLAGS[@]}"
BIN_DIR="$(swift build -c "$BUILD_CONFIGURATION" "${SWIFT_FLAGS[@]}" --show-bin-path)"
BIN_PATH="$BIN_DIR/Pata"

if [ ! -x "$BIN_PATH" ]; then
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

# Copy SPM resource bundles into Contents/Resources
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
    if [ -d "$bundle" ]; then
        echo "==> Copying resource bundle: $(basename "$bundle")..."
        cp -R "$bundle" "$APP_DIR/Contents/Resources/"
    fi
done
shopt -u nullglob

echo "==> Signing App Bundle with $SIGNING_IDENTITY..."
codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "==> Done! App bundle successfully built at $APP_DIR ($(du -sh "$APP_DIR" | cut -f1))"
