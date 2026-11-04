#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_SRC="build/bin/Pata.app"
if [ "${1:-}" != "--skip-build" ] || [ ! -d "$APP_SRC" ]; then
    ./scripts/build_swift_app.sh release
fi

codesign --verify --deep --strict "$APP_SRC"

echo "==> Stopping running pata instances..."
killall pata 2>/dev/null || true
sleep 0.5

DEST="/Applications/Pata.app"
echo "==> Installing to $DEST..."
rm -rf "$DEST" "/Applications/pata.app"
cp -R "$APP_SRC" "$DEST"

echo "==> Verifying preserved app signature..."
codesign --verify --deep --strict "$DEST"

echo "==> Registering with macOS LaunchServices..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" 2>/dev/null || true

echo "==> Pata.app successfully installed to $DEST ($(du -sh "$DEST" | cut -f1))"
