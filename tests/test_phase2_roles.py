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
        if item.get('generated'): continue
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
