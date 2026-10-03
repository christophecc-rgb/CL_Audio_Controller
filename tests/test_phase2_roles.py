import json
from pathlib import Path
import pytest
import importlib.util
_spec=importlib.util.spec_from_file_location("cl_role_install",Path(__file__).resolve().parents[1]/"packaging/role_install.py")
_module=importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_module)
manifest,RoleInstaller=_module.manifest,_module.RoleInstaller

# packaging is also a third-party package; load local engine explicitly.

@pytest.mark.parametrize('role',['show_server','ableton_reader','mtc_logic','control_station','show_backup','diagnostics','custom'])
def test_roles_symmetric_no_implicit_services(tmp_path,role):
    m=manifest(role,custom=['network_manager'] if role=='custom' else [])
    assert not m['services'] and 'rtp_agent' not in m['components']
    if role in ('show_server','control_station','diagnostics','mtc_logic'):
        assert not any(item['target'].startswith('@LIVE/') for item in m['component_details'].values())
    kit=tmp_path/'kit'; kit.mkdir();home=tmp_path/'home'
    (home/'Applications/Ableton Live 12 Suite.app').mkdir(parents=True)
    for item in m['component_details'].values():
        if item.get('generated') or _module.is_external(item): continue
        source=kit/item['source'];source.mkdir(parents=True);(source/'fixture').write_text('component')
    if role=='show_backup': (kit/'SCENE_BACKUP_HMAC_RX_VALIDATED').write_text('integration validated test fixture')
    engine=RoleInstaller(home,kit)
    result=engine.install(m,'migrate','https://server.local:8443')
    assert result['ok'] and engine.validate(m)['ok']
    assert engine.record.parent.stat().st_mode & 0o777 == 0o700
    assert json.loads(engine.record.read_text())['manifest']['role']==role
    engine.uninstall(m)
    assert all(not engine.target(item).exists() for item in m['component_details'].values())
    assert engine.record.exists()


def test_optional_rtp_and_migration_preserves_config(tmp_path):
    reader=manifest('ableton_reader',['rtp']); assert reader['services']==['com.claudio.midi-rtp-agent']
    with pytest.raises(ValueError): manifest('control_station',['rtp'])
    m=manifest('diagnostics');kit=tmp_path/'kit';home=tmp_path/'home';engine=RoleInstaller(home,kit)
    for item in m['component_details'].values(): (kit/item['source']).mkdir(parents=True)
    old=home/'Applications/CL Audio Controller.app';old.mkdir(parents=True)
    plist=home/'Library/LaunchAgents/com.claudio.midi-network-monitor.plist';plist.parent.mkdir(parents=True);plist.write_text('old')
    config=engine.record.parent/'network-config.json';config.parent.mkdir(parents=True,exist_ok=True);config.write_text('keep exact bytes')
    result=engine.install(m,'keep');assert not result['ok'] and old.exists() and plist.exists()
    result=engine.install(m,'migrate');assert result['ok'] and not old.exists() and not plist.exists()
    assert config.read_text()=='keep exact bytes'
    engine.uninstall(m);assert config.read_text()=='keep exact bytes'


def test_preflight_missing_external_and_no_mutation(tmp_path):
    engine=RoleInstaller(tmp_path/'home',tmp_path/'kit')
    with pytest.raises(FileNotFoundError): engine.install(manifest('show_server'),'migrate')
    assert not engine.home.exists()
    with pytest.raises(ValueError): manifest('custom')


def test_optional_agent_uninstall_uses_installed_manifest(tmp_path):
    home=tmp_path/'home';kit=tmp_path/'kit';engine=RoleInstaller(home,kit)
    (home/'Applications/Ableton Live 12 Suite.app').mkdir(parents=True)
    m=manifest('ableton_reader',['rtp'])
    for item in m['component_details'].values():
        source=kit/item['source'];source.mkdir(parents=True)
        if item.get('service'):
            executable=source/'Contents/MacOS'/source.stem;executable.parent.mkdir(parents=True);executable.write_text('fixture')
    assert engine.install(m,'migrate')['ok']
    agent=home/'Library/LaunchAgents/com.claudio.midi-rtp-agent.plist';assert agent.exists()
    engine.uninstall(manifest('ableton_reader'))
    assert not agent.exists() and not engine.target(m['component_details']['rtp_agent']).exists()


def test_external_show_backup_absent_from_kit_and_validate(tmp_path):
    kit = tmp_path / 'kit'
    kit.mkdir()
    (kit / 'SCENE_BACKUP_HMAC_RX_VALIDATED').write_text('validated fixture')
    engine = RoleInstaller(tmp_path / 'home', kit)
    m = manifest('custom', custom=['show_backup'])
    engine.preflight(m)
    assert engine.validate(m)['missing'] == []
    assert engine.install(m, 'migrate')['ok']
    record = json.loads(engine.record.read_text())
    assert record['installed_paths'] == []
    assert record['manifest']['components'] == ['show_backup']
    assert not engine.target(m['component_details']['show_backup']).exists()


def test_show_backup_role_only_requires_local_abletonosc(tmp_path):
    kit = tmp_path / 'kit'
    home = tmp_path / 'home'
    (home / 'Applications/Ableton Live 12 Suite.app').mkdir(parents=True)
    m = manifest('show_backup')
    source = kit / m['component_details']['ableton_osc']['source']
    source.mkdir(parents=True)
    (source / 'fixture').write_text('local AbletonOSC')
    (kit / 'SCENE_BACKUP_HMAC_RX_VALIDATED').write_text('validated fixture')
    engine = RoleInstaller(home, kit)
    assert engine.install(m, 'migrate')['ok']
    target = engine.target(m['component_details']['ableton_osc'])
    assert (target / 'fixture').read_text() == 'local AbletonOSC'
    assert json.loads(engine.record.read_text())['installed_paths'] == [str(target)]
    assert not (kit / m['component_details']['show_backup']['source']).exists()


@pytest.mark.parametrize('migration', ['keep', 'migrate', 'remove'])
def test_external_not_copied_retired_or_owned_even_in_legacy_manifest(tmp_path, migration):
    from unittest import mock
    kit = tmp_path / 'kit'
    m = manifest('custom', custom=['show_backup'])
    engine = RoleInstaller(tmp_path / 'home', kit)
    external = engine.target(m['component_details']['show_backup'])
    external.mkdir(parents=True)
    (external / 'receiver').write_text('external original')
    backup = external.with_name(external.stem + '.backup-old.app')
    backup.mkdir()
    (backup / 'receiver').write_text('external backup')
    old_backup = external.with_name(external.name + '.sauvegarde_old')
    old_backup.mkdir()
    engine.record.parent.mkdir(parents=True)
    # Include a normalized alias: historical data must not claim external ownership.
    alias = external.parent / '..' / 'Applications' / external.name
    (engine.record.parent / 'CL_Suite_install_manifest.tsv').write_text(
        '\t'.join(map(str, [external, backup, old_backup, alias])) + '\n')
    source = kit / m['component_details']['show_backup']['source']
    source.mkdir(parents=True)
    (source / 'receiver').write_text('must never be copied')
    (kit / 'SCENE_BACKUP_HMAC_RX_VALIDATED').write_text('validated fixture')
    # An embedded external copy is deliberately absent from the integrity manifest.
    (kit.parent / 'COMPONENTS_SHA256.txt').write_text('')
    assert not [item for item in engine.audit(m) if item['kind'] != 'configuration']
    with mock.patch.object(engine, 'retire', wraps=engine.retire) as retire, \
         mock.patch.object(_module.shutil, 'copytree', wraps=_module.shutil.copytree) as copytree:
        assert engine.install(m, migration)['ok']
        assert json.loads(engine.record.read_text())['installed_paths'] == []
        result = engine.uninstall(m)
        assert result['removed_components'] == []
        retire.assert_not_called()
        copytree.assert_not_called()
    assert (external / 'receiver').read_text() == 'external original'
    assert (backup / 'receiver').read_text() == 'external backup'
    assert old_backup.exists()


def test_external_hmac_gate_still_blocks_before_any_installation(tmp_path):
    m = manifest('custom', custom=['show_backup', 'network_manager'])
    kit = tmp_path / 'kit'
    local = kit / m['component_details']['network_manager']['source']
    local.mkdir(parents=True)
    engine = RoleInstaller(tmp_path / 'home', kit)
    with pytest.raises(ValueError, match='Récepteur CL Show Backup externe : validation HMAC requise avant installation'):
        engine.install(m, 'migrate')
    assert not engine.home.exists()
    assert not engine.record.exists()


def test_external_service_is_never_a_local_agent(tmp_path, monkeypatch):
    from unittest import mock
    catalog = json.loads(_module.CATALOG_PATH.read_text())
    label = 'com.claudio.midi-network-monitor'
    catalog['components']['show_backup']['service'] = label
    catalog['components']['show_backup']['target'] = '@LIVE/Remote Scripts/ExternalReceiver'
    catalog['components']['show_backup']['dependencies'] = ['Max for Live']
    catalog_path = tmp_path / 'catalog.json'
    catalog_path.write_text(json.dumps(catalog))
    monkeypatch.setattr(_module, 'CATALOG_PATH', catalog_path)
    m = manifest('custom', custom=['show_backup'])
    assert m['services'] == []
    assert label not in m['forbidden_services']
    # Exercise an older supplied manifest that still lists the external service.
    m['services'] = [label]
    kit = tmp_path / 'kit'
    kit.mkdir()
    (kit / 'SCENE_BACKUP_HMAC_RX_VALIDATED').write_text('validated fixture')
    engine = RoleInstaller(tmp_path / 'home', kit)
    plist = engine.home / 'Library/LaunchAgents' / (label + '.plist')
    plist.parent.mkdir(parents=True)
    plist.write_text('external agent original')
    with mock.patch.object(engine, 'agent') as agent:
        engine.preflight(m)  # No embedded executable or local Live/M4L required.
        assert engine.install(m, 'remove')['ok']
        assert engine.validate(m)['missing_agents'] == []
        engine.uninstall(m)
        agent.assert_not_called()
    assert plist.read_text() == 'external agent original'


def test_local_component_still_required_verified_copied_and_removed(tmp_path):
    import hashlib
    m = manifest('custom', custom=['network_manager'])
    engine = RoleInstaller(tmp_path / 'home', tmp_path / 'kit')
    with pytest.raises(FileNotFoundError, match='Composant absent du kit'):
        engine.preflight(m)
    assert not engine.home.exists()
    assert engine.validate(m)['missing'] == ['network_manager']
    item = m['component_details']['network_manager']
    source = engine.kit / item['source']
    source.mkdir(parents=True)
    fixture = source / 'fixture'
    fixture.write_text('local original')
    integrity = engine.kit.parent / 'COMPONENTS_SHA256.txt'
    key = fixture.relative_to(engine.kit.parent)
    integrity.write_text('0' * 64 + '  ' + str(key) + '\n')
    with pytest.raises(ValueError, match='Intégrité du kit invalide'):
        engine.install(m, 'migrate')
    assert not engine.home.exists()
    integrity.write_text(hashlib.sha256(fixture.read_bytes()).hexdigest() + '  ' + str(key) + '\n')
    assert engine.install(m, 'migrate')['ok']
    target = engine.target(item)
    assert (target / 'fixture').read_text() == 'local original'
    assert json.loads(engine.record.read_text())['installed_paths'] == [str(target)]
    assert engine.uninstall(m)['removed_components'] == ['network_manager']
    assert not target.exists()
