#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_SRC="build/bin/Pata.app"
if [ ! -d "$APP_SRC" ]; then
    echo "==> Application bundle not found. Building release bundle first..."
    ./scripts/build_swift_app.sh release
fi

echo "==> Stopping running pata instances..."
killall pata 2>/dev/null || true
sleep 0.5

DEST="/Applications/pata.app"
echo "==> Installing to $DEST..."
rm -rf "$DEST"
cp -R "$APP_SRC" "$DEST"

echo "==> Signing installed app bundle..."
codesign --force --deep --sign - "$DEST" 2>/dev/null || true

echo "==> Registering with macOS LaunchServices..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" 2>/dev/null || true

echo "==> Pata.app successfully installed to $DEST ($(du -sh "$DEST" | cut -f1))"
