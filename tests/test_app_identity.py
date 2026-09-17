import json
import plistlib
import shutil
import tempfile
import unittest
from pathlib import Path
from scripts.verify_app_identity import verify

ROOT = Path(__file__).resolve().parents[1]


class AppIdentityTests(unittest.TestCase):
    def test_unique_names_colours_and_icon_labels(self):
        identities = json.loads((ROOT/'resources/app_identity.json').read_text())
        for field in ('name', 'color', 'icon', 'label'):
            self.assertEqual(len(identities), len({a[field] for a in identities}), field)
        self.assertEqual(next(a['label'] for a in identities if a['name'] == 'CL Cue Editor'), 'CUE EDITOR')

    def test_packaged_icon_mixup_and_missing_app_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = Path(tmp)/'CL Audio Export.app'
            resources = app/'Contents/Resources'
            resources.mkdir(parents=True)
            info = {'CFBundleName':'CL Audio Export', 'CFBundleDisplayName':'CL Audio Export', 'CFBundleIconFile':'icon.icns'}
            (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
            shutil.copy2(ROOT/'assets/app_icons/CL_Audio_Export.icns', resources/'icon.icns')
            self.assertEqual(verify(tmp, ['CL Audio Export']), [])
            shutil.copy2(ROOT/'assets/app_icons/CL_Audio_Show_Control.icns', resources/'icon.icns')
            self.assertTrue(any('icône non canonique' in e for e in verify(tmp)))
            self.assertTrue(any('Application absente' in e for e in verify(tmp, ['CL Cue Editor'])))
            info['CFBundleDisplayName'] = 'CL Show Audio Builder'
            (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
            self.assertTrue(any('CFBundleDisplayName' in e for e in verify(tmp)))
