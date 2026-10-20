#!/bin/bash
#
# Builds Shinobi and installs it into /Applications.
#
# A release build by default: the debug build is noticeably slower at page capture, which is
# the part you notice, and there is no reason to run debug for real work.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${SHINOBI_CONFIG:-release}"
DESTINATION="${SHINOBI_DESTINATION:-/Applications}"
APP="$DESTINATION/Shinobi.app"

echo "==> Building Shinobi ($CONFIG)"
"$ROOT/Scripts/build-app.sh" "$CONFIG"

if [ -d "$APP" ]; then
    echo "==> Replacing the copy already in $DESTINATION"
    # Quit a running copy first: replacing the bundle underneath a live process leaves it in
    # a state where it half-works until relaunch, which is worse than a clear stop.
    if pgrep -f "$APP/Contents/MacOS/Shinobi" >/dev/null 2>&1; then
        echo "    Shinobi is running — quitting it"
        osascript -e 'tell application "Shinobi" to quit' >/dev/null 2>&1 || true
        sleep 2
        pkill -f "$APP/Contents/MacOS/Shinobi" 2>/dev/null || true
    fi
    rm -rf "$APP"
fi

echo "==> Installing to $DESTINATION"
cp -R "$ROOT/.build/Shinobi.app" "$APP"

# Locally built bundles carry no quarantine flag, but a copy that has been through a zip or a
# download does. Clearing it here means the first launch does not hit Gatekeeper.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# Nudge Launch Services so the icon and the app appear without a logout.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP" >/dev/null 2>&1 || true

echo
echo "Installed: $APP"
if [ -z "${SHINOBI_SIGNING_IDENTITY:-}" ]; then
    echo
    echo "Note: this build is ad-hoc signed, which is fine on this Mac and nowhere else."
    echo "For a copy that runs on another machine, build with a Developer ID and notarise it:"
    echo "  SHINOBI_SIGNING_IDENTITY=\"Developer ID Application: ...\" Scripts/install.sh"
fi
echo
echo "Open it from Applications, or:  open -a Shinobi"
