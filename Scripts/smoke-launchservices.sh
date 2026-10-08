#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p evidence
python3 - "$ROOT" <<'PY'
import json, subprocess, sys, time
from pathlib import Path
root=Path(sys.argv[1]); report=root/'evidence/launchservices-smoke.json'
if report.exists(): report.unlink()
subprocess.run(['open','-n',str(root/'dist/NearGuard.app'),'--args','--smoke-test','--smoke-report',str(report)],check=True)
deadline=time.monotonic()+20
while not report.exists() and time.monotonic()<deadline: time.sleep(0.2)
assert report.exists(), 'LaunchServices did not produce smoke report'
r=json.loads(report.read_text())
assert r['systemQueries']==0 and r['systemPairedEnumerations']==0 and r['systemConnectionAttempts']==0
assert r['loginRegistrationAttempts']==0 and r['loginStatusReads']==0
assert r['passed'] and r['nativeWindowRendered'] and not r['bluetoothManagerCreated'] and r['lockRequests']==0 and r['permissionPromptsRequested']==0
print(json.dumps(r,ensure_ascii=False,indent=2)); print('LAUNCHSERVICES SAFE SMOKE PASSED')
PY
