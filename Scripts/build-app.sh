#!/bin/bash
#
# Assembles Shinobi.app from the SwiftPM build products.
#
# Shinobi is not distributed through the Mac App Store — per-container proxying, arbitrary
# case-file locations and ScreenCaptureKit all sit outside the App Sandbox — so the
# release path is Developer ID signing plus notarisation. Until a signing identity exists
# on this machine the bundle is ad-hoc signed, which is enough to run locally.
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build/$CONFIG"
APP="$ROOT/.build/Shinobi.app"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" --package-path "$ROOT"

echo "==> Building icon"
# Generated from the iconset rather than committed as a binary, so editing a PNG is enough
# and there is only ever one source of truth for what the icon is.
ICONSET="$ROOT/Resources/Icon/Shinobi.iconset"
if [ -d "$ICONSET" ]; then
    iconutil -c icns "$ICONSET" -o "$ROOT/.build/Shinobi.icns"
else
    echo "    no iconset at $ICONSET — bundle will use the generic app icon"
fi

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/Shinobi" "$APP/Contents/MacOS/Shinobi"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
[ -f "$ROOT/.build/Shinobi.icns" ] && cp "$ROOT/.build/Shinobi.icns" "$APP/Contents/Resources/Shinobi.icns"

# SwiftPM emits resource bundles alongside the binary; carry any across.
for bundle in "$BUILD_DIR"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

echo "==> Signing"
if [ -n "${SHINOBI_SIGNING_IDENTITY:-}" ]; then
    # Release path. The hardened runtime is required for notarisation.
    codesign --force --deep --options runtime --timestamp \
        --entitlements "$ROOT/Resources/Shinobi.entitlements" \
        --sign "$SHINOBI_SIGNING_IDENTITY" "$APP"
    echo "    signed with Developer ID: $SHINOBI_SIGNING_IDENTITY"
else
    codesign --force --deep --sign - "$APP"
    echo "    ad-hoc signed (set SHINOBI_SIGNING_IDENTITY for a Developer ID build)"
fi

echo "==> $APP"
