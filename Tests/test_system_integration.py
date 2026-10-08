"""Static integration guardrails; not hardware validation."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
class SystemIntegrationTests(unittest.TestCase):
    def test_native_public_adapter_and_no_link_mutation(self):
        source = (ROOT/'Sources/NearGuard/SystemBluetooth.swift').read_text() if (ROOT/'Sources/NearGuard/SystemBluetooth.swift').exists() else ''
        for api in ['import IOBluetooth', 'IOBluetoothDevice.pairedDevices()', '.isConnected()', '.rawRSSI()']:
            self.assertIn(api, source)
        for forbidden in ['openConnection(', 'closeConnection(', 'IOBluetoothDeviceInquiry', 'IOBluetoothDevicePair']:
            self.assertNotIn(forbidden, source)
    def test_mode_and_safe_instrumentation(self):
        model = (ROOT/'Sources/NearGuard/AppModel.swift').read_text()
        main = (ROOT/'Sources/NearGuard/main.swift').read_text()
        self.assertIn('SystemPollingSession', model)
        self.assertIn('systemQueries', main)
        self.assertIn('systemConnectionAttempts', main)
        self.assertIn('systemPairedEnumerations', main)
        self.assertIn('兼容性待验证', (ROOT/'Sources/NearGuard/Views.swift').read_text())
if __name__ == '__main__': unittest.main()
