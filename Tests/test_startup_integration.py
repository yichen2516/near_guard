"""Source wiring checks complement runtime/policy tests, not OS/hardware proof."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
class StartupIntegrationTests(unittest.TestCase):
    def test_every_fresh_session_has_grace_even_after_duplicate_power_callbacks(self):
        source = (ROOT/'Sources/NearGuard/AppModel.swift').read_text()
        session = source.split('private func beginSession()',1)[1].split('func stopMonitoring(',1)[0]
        self.assertIn('\n        engine.wake(now: now)\n', session)
        self.assertNotIn('if let until', session)
    def test_native_login_explicit_writes_and_safe_guard(self):
        p = ROOT/'Sources/NearGuard/LoginItems.swift'
        source = p.read_text() if p.exists() else ''
        for token in ['SMAppService.mainApp.status', 'SMAppService.mainApp.register()', 'SMAppService.mainApp.unregister()', 'SMAppService.openSystemSettingsLoginItems()', 'LoginItemController']:
            self.assertIn(token, source)
    def test_model_restore_and_runtime_intent_separation(self):
        source = (ROOT/'Sources/NearGuard/AppModel.swift').read_text()
        for token in ['desiredAutomaticLock', 'MonitoringPreferences', 'restoreMonitoringIfEligible', 'CBManager.authorization == .allowedAlways', 'refreshEffectiveLock', 'stopMonitoring(preserveIntent: true)', 'setAutomaticLock']:
            self.assertIn(token, source)
        main = (ROOT/'Sources/NearGuard/main.swift').read_text()
        for token in ['loginRegistrationAttempts', 'loginStatusReads', 'restoreMonitoringIfEligible', 'showSettingsOnLaunch']:
            self.assertIn(token, main)
if __name__ == '__main__': unittest.main()
