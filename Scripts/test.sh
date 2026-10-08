#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p evidence
swift test 2>&1 | tee evidence/tests-final.log
swift test -c release 2>&1 | tee evidence/tests-release-final.log
python3 Tests/test_system_integration.py 2>&1 | tee evidence/system-integration-green.log
python3 Tests/test_startup_integration.py 2>&1 | tee evidence/startup-wiring-green.log
python3 Tests/test_preferences_process.py 2>&1 | tee evidence/preferences-process-green.log
