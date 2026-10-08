#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/Scripts/test.sh"
"$ROOT/Scripts/build.sh"
"$ROOT/Scripts/smoke.sh"
"$ROOT/Scripts/smoke-launchservices.sh"
if [[ "${1:-}" == "--with-ios" ]]; then "$ROOT/Scripts/build-ios.sh"; fi
python3 "$ROOT/Scripts/report-system.py"
