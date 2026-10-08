"""App-icon packaging regression: source assets and optional built bundle."""
import json
import plistlib
import struct
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'iOS/NearGuardPhone/Assets.xcassets'

class IOSIconTests(unittest.TestCase):
    def test_catalog_exists(self):
        self.assertTrue((ASSETS / 'Contents.json').is_file(), 'Asset catalog is missing')

    def test_universal_icon_is_opaque_1024_png(self):
        path = ASSETS / 'AppIcon.appiconset/AppIcon.png'
        self.assertTrue(path.is_file(), 'iOS app icon is missing')
        data = path.read_bytes()
        self.assertEqual(data[:8], b'\x89PNG\r\n\x1a\n')
        self.assertEqual(struct.unpack('>II', data[16:24]), (1024, 1024))
        self.assertEqual(data[25], 2, 'App icon must be opaque RGB, no alpha')
        import zlib
        offset = 8; compressed = b''
        while offset < len(data):
            size = struct.unpack('>I', data[offset:offset + 4])[0]
            if data[offset + 4:offset + 8] == b'IDAT':
                compressed += data[offset + 8:offset + 8 + size]
            offset += 12 + size
        raw = zlib.decompress(compressed)
        self.assertTrue(any(raw[1:4]), 'Icon drawing failed: first RGB pixel is black')
        manifest = json.loads((path.parent / 'Contents.json').read_text())
        self.assertEqual(manifest['images'], [{'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}])

    def test_project_compiles_assets_and_selects_icon(self):
        project = (ROOT / 'iOS/NearGuardPhone.xcodeproj/project.pbxproj').read_text()
        self.assertIn('Assets.xcassets in Resources', project)
        self.assertIn('lastKnownFileType = folder.assetcatalog', project)
        self.assertEqual(project.count('ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;'), 2)

    @unittest.skipUnless('--built' in sys.argv, 'build verification requested separately')
    def test_built_bundle_includes_compiled_icon(self):
        app = ROOT / '.build/iOS/Build/Products/Debug-iphonesimulator/NearGuardPhone.app'
        self.assertTrue((app / 'Assets.car').is_file())
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        self.assertEqual(info['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconName'], 'AppIcon')
        self.assertTrue(info['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconFiles'])

if __name__ == '__main__':
    unittest.main(argv=[sys.argv[0]])
