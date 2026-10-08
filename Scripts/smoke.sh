#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p evidence
APP="$ROOT/dist/NearGuard.app"
[[ -x "$APP/Contents/MacOS/NearGuard" ]] || "$ROOT/Scripts/build.sh"
"$APP/Contents/MacOS/NearGuard" --smoke-test --smoke-report "$ROOT/evidence/smoke.json" 2>&1 | tee "$ROOT/evidence/smoke-launch.log"
python3 - "$ROOT/evidence/smoke.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
assert r['passed'] and r['nativeWindowRendered'] and r['runLoopExercised']
assert not r['bluetoothManagerCreated'] and not r['monitoring'] and not r['realLockEnabled']
assert r['lockRequests']==0 and r['permissionPromptsRequested']==0
assert r['systemQueries']==0 and r['systemPairedEnumerations']==0 and r['systemConnectionAttempts']==0
assert r['loginRegistrationAttempts']==0 and r['loginStatusReads']==0
print('SAFE SMOKE PASSED: native window, no BLE manager, no lock request')
PY
