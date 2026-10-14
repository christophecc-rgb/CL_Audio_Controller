"""FULL payload, role selection and upgrades without building or installing on the Mac."""
import importlib.util
import json
from pathlib import Path
import plistlib

import pytest

ROOT = Path(__file__).resolve().parents[1]


def load(relative):
    spec = importlib.util.spec_from_file_location(Path(relative).stem, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


roles = load('packaging/role_install.py')
kit_check = load('scripts/verify_full_kit.py')


@pytest.fixture
def catalog():
    return json.loads((ROOT / 'config/installation_roles.json').read_text())


def bundle(path):
    (path / 'Contents/MacOS').mkdir(parents=True)
    (path / 'Contents/MacOS/fixture').write_text('new version')
    (path / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': 'fixture'}))


def payload(root, catalog, layout):
    for name, release in catalog['full_kit_applications'].items():
        if layout == 'release' and release is None:
            continue
        bundle(root / (release if layout == 'release' else 'Applications/' + name))
    if layout == 'components':
        (root / catalog['components']['arrangement_builder_script']['source']).mkdir(parents=True)


@pytest.mark.parametrize('layout', ['release', 'components'])
@pytest.mark.parametrize('name', ['CL Audio Export.app', 'CL Arrangement Builder.app'])
def test_full_kit_cannot_omit_production_apps(tmp_path, catalog, layout, name):
    payload(tmp_path, catalog, layout)
    assert kit_check.verify(tmp_path, catalog, layout)['ok']
    path = tmp_path / (catalog['full_kit_applications'][name] if layout == 'release' else 'Applications/' + name)
    (path / 'Contents/Info.plist').unlink()
    with pytest.raises(ValueError, match=name):
        kit_check.verify(tmp_path, catalog, layout)


def test_builder_script_required_in_exported_kit(tmp_path, catalog):
    payload(tmp_path, catalog, 'components')
    (tmp_path / catalog['components']['arrangement_builder_script']['source']).rmdir()
    with pytest.raises(ValueError, match='Dépendance'):
        kit_check.verify(tmp_path, catalog, 'components')


def test_applications_roles_and_native_selection_share_catalog(catalog):
    minimum = {'CL Show Control.app', 'CL ShowCue.app', 'CL Cue Editor.app',
               'CL Audio Export.app', 'CL Arrangement Builder.app'}
    assert minimum <= catalog['full_kit_applications'].keys()
    assert 'audio_export' in roles.manifest('show_server')['components']
    assert {'arrangement_builder', 'arrangement_builder_script'} <= set(roles.manifest('ableton_reader')['components'])
    selected = roles.manifest('custom', custom=['audio_export', 'arrangement_builder'])
    assert {'show_control', 'audio_export', 'arrangement_builder', 'arrangement_builder_script'} == set(selected['components'])
    assert not selected['services']
    native = (ROOT / 'packaging/CLSuiteInstallerApp.m').read_text()
    assert 'self.roleCatalog[@"roles"][roleNames[role]][@"components"]' in native
    assert '@[@"audio_export",' in native and '@[@"arrangement_builder",' in native
    for key in ('audio_export', 'arrangement_builder'):
        name = Path(catalog['components'][key]['source']).name
        assert name in catalog['full_kit_applications']


@pytest.mark.parametrize('missing', ['audio_export', 'arrangement_builder', 'arrangement_builder_script'])
def test_missing_selected_app_or_script_prevents_any_install(tmp_path, catalog, monkeypatch, missing):
    monkeypatch.setenv('CL_SUITE_ASSUME_M4L', '1')
    kit = tmp_path / 'kit'
    home = tmp_path / 'home'
    (home / 'Applications/Ableton Live 12 Suite.app').mkdir(parents=True)
    plan = roles.manifest('custom', custom=['audio_export', 'arrangement_builder'])
    for key, item in plan['component_details'].items():
        if key != missing:
            (kit / item['source']).mkdir(parents=True)
    engine = roles.RoleInstaller(home, kit)
    with pytest.raises(FileNotFoundError):
        engine.install(plan, 'migrate')
    assert not engine.record.exists()
    assert not engine.target(catalog['components']['audio_export']).exists()


def test_install_upgrade_validate_and_preserve_old_versions(tmp_path, catalog):
    kit = tmp_path / 'kit'
    home = tmp_path / 'home'
    (home / 'Applications/Ableton Live 12 Suite.app').mkdir(parents=True)
    plan = roles.manifest('custom', custom=['audio_export', 'arrangement_builder'])
    for item in plan['component_details'].values():
        if item['source'].endswith('.app'):
            bundle(kit / item['source'])
        else:
            (kit / item['source']).mkdir(parents=True)
    engine = roles.RoleInstaller(home, kit)
    for key in ('audio_export', 'arrangement_builder'):
        old = engine.target(catalog['components'][key])
        old.mkdir(parents=True)
        (old / 'old-version').write_text('keep backup')
        legacy = home / catalog['components'][key]['legacy_targets'][0]
        legacy.mkdir(parents=True)
        (legacy / 'old-version').write_text('keep legacy backup')
    result = engine.install(plan, 'migrate')
    assert result['ok'] and engine.validate(plan)['ok']
    assert len(list(engine.trash.rglob('old-version'))) == 4
    for key in ('audio_export', 'arrangement_builder'):
        assert (engine.target(catalog['components'][key]) / 'Contents/MacOS/fixture').read_text() == 'new version'
    assert engine.target(catalog['components']['arrangement_builder_script']).exists()
    engine.uninstall(plan)
    assert all(not engine.target(item).exists() for item in plan['component_details'].values())


def test_build_and_export_gate_payload_before_archiving():
    for filename, layout in [('build_release.sh', 'release'), ('export_transport_kit.command', 'components')]:
        source = (ROOT / 'scripts' / filename).read_text()
        assert 'scripts/verify_full_kit.py' in source
        assert '--layout ' + layout in source
        assert source.index('scripts/verify_full_kit.py') < source.index('ditto -c -k')
        assert 'CL Audio Export.app' in source and 'CL Arrangement Builder.app' in source
    assert "['show_audio_builder_desktop.py']" in (ROOT / 'CL Show Audio Builder.spec').read_text()
    source = (ROOT / 'scripts/export_transport_kit.command').read_text()
    assert '"Arrangement Builder Live.spec"' in source
    assert '"$BUILDER_DIR"' in source
    wrapper = (ROOT / 'packaging/Installer_La_Suite_CL.app.sh').read_text()
    assert 'CL Audio Export' in wrapper and 'show-audio-builder' in wrapper
