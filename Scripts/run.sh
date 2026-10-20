#!/bin/bash
# Builds the bundle and launches it, tailing stderr into this terminal.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/Scripts/build-app.sh" "${1:-debug}"
exec "$ROOT/.build/Shinobi.app/Contents/MacOS/Shinobi"
