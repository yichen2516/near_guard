#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p evidence
python3 Tests/test_ios_icon.py
xcodebuild -project iOS/NearGuardPhone.xcodeproj -scheme NearGuardPhone -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/iOS CODE_SIGNING_ALLOWED=NO build 2>&1 | tee evidence/build-ios-simulator.log
python3 Tests/test_ios_icon.py --built
printf '
Simulator build only: .build/iOS/Build/Products/Debug-iphonesimulator/NearGuardPhone.app
'
