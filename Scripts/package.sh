#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/Scripts/build.sh"
mkdir -p "$ROOT/dist"
ditto "$ROOT/build/Build/Products/Release/CodexQuotaRing.app" "$ROOT/dist/Codex Quota Ring.app"
codesign --force --deep --sign - "$ROOT/dist/Codex Quota Ring.app"
codesign --verify --deep --strict "$ROOT/dist/Codex Quota Ring.app"
ditto -c -k --sequesterRsrc --keepParent "$ROOT/dist/Codex Quota Ring.app" "$ROOT/dist/CodexQuotaRing-macOS.zip"
echo "Packaged: $ROOT/dist/Codex Quota Ring.app"

python3 "$ROOT/Scripts/archive-source.py"
