#!/usr/bin/env python3
"""Aggregate actual local outputs; never infer hardware or energy success."""
from pathlib import Path
import hashlib, json, re, subprocess
ROOT = Path(__file__).resolve().parents[1]
E = ROOT / 'evidence'
expected = sum(len(re.findall(r'func test\w+\(', p.read_text())) for p in (ROOT/'Tests/NearGuardCoreTests').glob('*.swift'))
def suite(path):
    text = path.read_text()
    matches = re.findall(r'Executed (\d+) tests, with (\d+) failures', text)
    assert matches, f'No XCTest result in {path}'
    count, failures = map(int, matches[-1])
    assert count == expected and failures == 0, (path, count, failures, expected)
    return {'tests': count, 'failures': failures, 'log': str(path.relative_to(ROOT))}
smokes = {}
for name in ['smoke', 'launchservices-smoke']:
    result = json.loads((E/f'{name}.json').read_text())
    assert result['passed'] and result['nativeWindowRendered']
    assert not result['bluetoothManagerCreated'] and not result['realLockEnabled'] and not result['monitoring']
    for field in ['systemQueries','systemPairedEnumerations','systemConnectionAttempts','permissionPromptsRequested','lockRequests','loginRegistrationAttempts','loginStatusReads']:
        assert result[field] == 0
    smokes[name] = result
app = ROOT/'dist/NearGuard.app'
signature = subprocess.run(['codesign','--verify','--deep','--strict',str(app)],capture_output=True,text=True)
assert signature.returncode == 0, signature.stderr
linked = subprocess.check_output(['otool','-L',str(app/'Contents/MacOS/NearGuard')],text=True)
assert 'IOBluetooth.framework' in linked and 'CoreBluetooth.framework' in linked
assert 'ServiceManagement.framework' in linked
(E/'system-linked-frameworks.log').write_text(linked)
sourcechecks = (E/'system-integration-green.log').read_text()
def python_count(path):
    text = path.read_text()
    matches = re.findall(r'Ran (\d+) tests?', text)
    assert matches and re.search(r'^OK$', text, re.M), path
    return int(matches[-1])
system_checks = python_count(E/'system-integration-green.log')
startup_checks = python_count(E/'startup-wiring-green.log')
process_checks = python_count(E/'preferences-process-green.log')
project = (ROOT/'iOS/NearGuardPhone.xcodeproj/project.pbxproj').read_text()
summary = {
    'debug': suite(E/'tests-final.log'), 'release': suite(E/'tests-release-final.log'),
    'staticIntegrationChecks': system_checks + startup_checks,
    'freshProcessPreferenceChecks': process_checks,
    'loginOSRegistration': 'NOT_TESTED', 'loginOrRebootLaunch': 'NOT_TESTED',
    'linkedServiceManagement': True,
    'nativeSignedApp': str(app), 'signatureVerified': True,
    'linkedIOBluetoothAndCoreBluetooth': True,
    'smokes': smokes,
    'hardwareCompatibility': 'NOT_VERIFIED', 'phoneEnergy': 'NOT_MEASURED',
    'realLockHardware': 'NOT_TESTED',
    'transportPolicy': 'observe existing OS links; 5s cadence; zero connection or pairing attempts',
    'iOSDevelopmentTeams': sorted(set(re.findall(r'DEVELOPMENT_TEAM = ([^;]+);', project))),
    'commands': ['./Scripts/test.sh','./Scripts/build.sh','./Scripts/smoke.sh','./Scripts/smoke-launchservices.sh','./Scripts/build-ios.sh','python3 Scripts/report-system.py'],
}
(E/'system-verification-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
# Refresh the existing manifest, retaining every prior entry and adding this mode.
manifest = E/'checksums.sha256'
paths = [line.split('  ',1)[1] for line in manifest.read_text().splitlines() if '  ' in line] if manifest.exists() else []
paths += ['Sources/NearGuard/SystemBluetooth.swift','Sources/NearGuardCore/SystemPollingSession.swift','Tests/NearGuardCoreTests/SystemBluetoothTests.swift','Tests/test_system_integration.py','Scripts/report-system.py','evidence/system-verification-summary.json','evidence/SYSTEM-BLUETOOTH.md']
paths += ['Sources/NearGuard/LoginItems.swift','Sources/NearGuardCore/LoginItemController.swift','Sources/NearGuardCore/MonitoringPreferences.swift','Tests/NearGuardCoreTests/LoginItemTests.swift','Tests/NearGuardCoreTests/PreferencesTests.swift','Tests/NearGuardCoreTests/AppStartupTests.swift','Tests/test_startup_integration.py','Tests/test_preferences_process.py','evidence/STARTUP-PREFERENCES.md','evidence/startup-wiring-green.log','evidence/preferences-process-green.log']
paths += ['evidence/preferences-process.json']
paths += [str(p.relative_to(ROOT)) for p in sorted(E.glob('startup-*.png'))]
paths += [str(p.relative_to(ROOT)) for p in sorted(E.glob('startup-*.json'))]
paths += [str(p.relative_to(ROOT)) for p in sorted(E.glob('persistent-lock-pane.*'))]
paths = [p for p in dict.fromkeys(paths) if (ROOT/p).is_file()]
manifest.write_text(''.join(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()+'  '+p+'\n' for p in paths))
for line in manifest.read_text().splitlines():
    digest, path = line.split('  ',1)
    assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest() == digest
print(json.dumps({'debug':summary['debug'],'release':summary['release'],'signatureVerified':True,'smokesPassed':True,'manifestEntriesVerified':len(paths),'hardwareCompatibility':'NOT_VERIFIED','phoneEnergy':'NOT_MEASURED'},indent=2))
