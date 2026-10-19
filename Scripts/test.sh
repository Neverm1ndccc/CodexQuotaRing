#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
xcodebuild -project "$ROOT/CodexQuotaRing.xcodeproj" -scheme CodexQuotaRing -configuration Debug -derivedDataPath "$ROOT/build" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
