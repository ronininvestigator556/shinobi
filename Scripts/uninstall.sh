#!/bin/bash
#
# Removes Shinobi and the data it keeps outside its bundle.
#
# Deliberately shows everything it intends to remove and waits for a yes. Two of the things it
# touches are not recoverable and are easy to under-appreciate:
#
#   Container data is every persona's cookies and logins. Removing it signs each identity out
#   of everything it was signed in to, and those sessions may have taken effort to establish.
#
#   Case signing keys are per case. Manifests already written still verify — the public key
#   travels inside the manifest — but without the private key a case can never be re-signed,
#   so any case you might still add to should be signed and exported before running this.
#
# Case files are never touched. They live wherever you saved them, they are the evidence, and
# a script that went looking for them to delete would be a bad idea.
set -euo pipefail

APP="${SHINOBI_APP:-/Applications/Shinobi.app}"
SUPPORT="$HOME/Library/Application Support/Shinobi"
WEBKIT="$HOME/Library/WebKit/com.shinobi.browser"
CACHES="$HOME/Library/Caches/com.shinobi.browser"
PREFS="$HOME/Library/Preferences/com.shinobi.browser.plist"
SAVED="$HOME/Library/Saved Application State/com.shinobi.browser.savedState"
HTTP="$HOME/Library/HTTPStorages"

ASSUME_YES=0
KEEP_KEYS=0
for arg in "$@"; do
    case "$arg" in
        --yes|-y) ASSUME_YES=1 ;;
        --keep-keys) KEEP_KEYS=1 ;;
        --help|-h)
            echo "Usage: uninstall.sh [--yes] [--keep-keys]"
            echo "  --yes        do not ask for confirmation"
            echo "  --keep-keys  leave case signing keys in the Keychain"
            exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

size_of() { [ -e "$1" ] && du -sh "$1" 2>/dev/null | cut -f1 || echo "-"; }
present()  { [ -e "$1" ] && echo yes || echo no; }

# Count what is in the Keychain before saying anything about it.
proxy_keys=$(security dump-keychain 2>/dev/null | grep -c 'com.shinobi.browser.proxy' || true)
signing_accounts=$(security dump-keychain 2>/dev/null \
    | grep -B12 'com.shinobi.browser.case-signing' \
    | grep '"acct"' | sed 's/.*="//; s/"$//' | sort -u || true)
signing_count=$(printf '%s\n' "$signing_accounts" | grep -c . || true)

echo "This will remove:"
echo
printf '  %-34s %-6s %s\n' "Application" "$(present "$APP")" "$APP"
printf '  %-34s %-6s %s\n' "Settings, watches, filter lists" "$(size_of "$SUPPORT")" "$SUPPORT"
printf '  %-34s %-6s %s\n' "Container data (cookies, logins)" "$(size_of "$WEBKIT")" "$WEBKIT"
printf '  %-34s %-6s %s\n' "Caches" "$(size_of "$CACHES")" "$CACHES"
printf '  %-34s %-6s %s\n' "Preferences" "$(present "$PREFS")" "$PREFS"
printf '  %-34s %-6s %s\n' "Saved window state" "$(present "$SAVED")" "$SAVED"
printf '  %-34s %-6s %s\n' "Proxy passwords (Keychain)" "$proxy_keys" "item(s)"
if [ "$KEEP_KEYS" -eq 1 ]; then
    printf '  %-34s %-6s %s\n' "Case signing keys (Keychain)" "kept" "$signing_count item(s) left in place"
else
    printf '  %-34s %-6s %s\n' "Case signing keys (Keychain)" "$signing_count" "item(s)"
fi
echo
echo "This will NOT remove your case files. They are wherever you saved them."
echo

if [ "$KEEP_KEYS" -eq 0 ] && [ "$signing_count" -gt 0 ]; then
    echo "Cases whose signing key is about to be removed:"
    printf '%s\n' "$signing_accounts" | sed 's/^/    /'
    echo
    echo "  Manifests already written for these still verify — the public key is inside the"
    echo "  manifest — but they can never be re-signed. If you may still add to one of these"
    echo "  cases, stop now, sign and export it first, or re-run with --keep-keys."
    echo
fi

if [ "$ASSUME_YES" -eq 0 ]; then
    printf 'Type "remove" to continue: '
    read -r answer
    [ "$answer" = "remove" ] || { echo "Nothing was removed."; exit 1; }
fi

echo
if pgrep -f "Shinobi.app/Contents/MacOS/Shinobi" >/dev/null 2>&1; then
    echo "==> Quitting Shinobi"
    osascript -e 'tell application "Shinobi" to quit' >/dev/null 2>&1 || true
    sleep 2
    pkill -f "Shinobi.app/Contents/MacOS/Shinobi" 2>/dev/null || true
fi

remove() { [ -e "$1" ] && { rm -rf "$1"; echo "    removed $1"; } || true; }

echo "==> Removing files"
remove "$APP"
remove "$SUPPORT"
remove "$WEBKIT"
remove "$CACHES"
remove "$PREFS"
remove "$SAVED"
for file in "$HTTP"/com.shinobi.browser*; do remove "$file"; done

echo "==> Removing Keychain items"
while security delete-generic-password -s com.shinobi.browser.proxy >/dev/null 2>&1; do :; done
echo "    proxy passwords removed"

if [ "$KEEP_KEYS" -eq 0 ]; then
    while security delete-generic-password -s com.shinobi.browser.case-signing >/dev/null 2>&1; do :; done
    echo "    case signing keys removed"
else
    echo "    case signing keys kept (--keep-keys)"
fi

# Preferences are cached by the system; without this a reinstall can inherit stale settings.
defaults read com.shinobi.browser >/dev/null 2>&1 && defaults delete com.shinobi.browser 2>/dev/null || true
killall cfprefsd 2>/dev/null || true

echo
echo "Shinobi has been removed. Your case files were not touched."
