import importlib.util
import plistlib
from pathlib import Path
import pytest
from release_version import RELEASE_VERSION, RELEASE_BUILD

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('stamp_bundles', ROOT / 'scripts/stamp_release_bundles.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def test_temporary_bundle_stamp_preserves_identity(tmp_path):
    p = tmp_path / 'Example.app/Contents/Info.plist'
    p.parent.mkdir(parents=True)
    with p.open('wb') as f:
        plistlib.dump({'CFBundleIdentifier': 'test.example', 'CFBundleVersion': '6'}, f)
    result = module.stamp(tmp_path, RELEASE_VERSION, RELEASE_BUILD)
    with p.open('rb') as f:
        data = plistlib.load(f)
    assert data['CFBundleIdentifier'] == 'test.example'
    assert data['CFBundleShortVersionString'] == '2.3.0'
    assert data['CFBundleVersion'] == '23001'
    assert result[0]['identifier'] == 'test.example'

def test_bundle_stamp_refuses_downgrade(tmp_path):
    p = tmp_path / 'Example.app/Contents/Info.plist'
    p.parent.mkdir(parents=True)
    with p.open('wb') as f:
        plistlib.dump({'CFBundleVersion': '99999'}, f)
    with pytest.raises(ValueError, match='downgrade'):
        module.stamp(tmp_path, RELEASE_VERSION, RELEASE_BUILD)
    with p.open('rb') as f:
        assert plistlib.load(f)['CFBundleVersion'] == '99999'
