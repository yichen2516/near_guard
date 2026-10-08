#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p evidence dist
swift build -c release 2>&1 | tee evidence/build-mac.log
BIN="$(swift build -c release --show-bin-path)"
APP="$ROOT/dist/NearGuard.app"
# Only replace our own generated bundle, never a source directory.
if [[ -e "$APP" && ! -f "$APP/Contents/Info.plist" ]]; then
  printf 'Refusing to replace unexpected path: %s
' "$APP" >&2; exit 1
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/NearGuard" "$APP/Contents/MacOS/NearGuard"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/NearGuard.icns ]]; then cp Resources/NearGuard.icns "$APP/Contents/Resources/"; fi
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - --identifier local.nearguard.mac "$APP"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tee evidence/codesign-verify.log
printf '
Built: %s
' "$APP"
