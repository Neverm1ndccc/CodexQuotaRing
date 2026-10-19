#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.build/Tools" "$ROOT/Documentation"
swiftc "$ROOT/Sources/Models/QuotaModels.swift" "$ROOT/Sources/Services/RingIconRenderer.swift" "$ROOT/Tools/render-rings.swift" -o "$ROOT/.build/Tools/render-rings"
"$ROOT/.build/Tools/render-rings" "$ROOT/Documentation/ring-preview.png"
