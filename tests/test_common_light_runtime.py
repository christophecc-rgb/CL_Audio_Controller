"""Real Light host + HTTP/security boundary, without opening OSC sockets."""
import hashlib
import hmac
import json
from unittest.mock import Mock
import pytest
from app_mode import common_light_capabilities
from common_light_runtime import create_common_light_app, load_common_host
from remote_security import canonical_request
from test_local_light_go import prepare_app
from app_mode import AppMode


@pytest.fixture
def host(tmp_path, monkeypatch):
    monkeypatch.setenv('CL_SECURITY_DIRECTORY', str(tmp_path / 'security'))
    return load_common_host()


@pytest.fixture
def ready(host, monkeypatch):
    ctx = prepare_app(monkeypatch, host, AppMode.LOCAL_LIGHT)
    ctx.state['connected'] = True
    monkeypatch.setattr(host, 'APP_CAPABILITIES', common_light_capabilities())
    monkeypatch.setattr(host, 'schedule_selected_scene_duration_refresh', Mock())
    monkeypatch.setattr(host, 'resolve_scene_clip_duration_async', Mock())
    monkeypatch.setattr(host, 'parse_scene_duration_seconds', Mock(return_value=60))
    for name in ('record_go_midi_expectations', 'send_midi_monitor_scene_context', 'copy_to_backup'):
        monkeypatch.setattr(host, name, Mock(side_effect=AssertionError(name)))
    backend = create_common_light_app(host)
    return backend, ctx


def test_no_product_services_constructed(tmp_path, monkeypatch):
    monkeypatch.setenv('CL_SECURITY_DIRECTORY', str(tmp_path))
    forbidden = Mock(side_effect=AssertionError('FULL service instantiated'))
    for path in ('hot_backup_sync.HotBackup', 'scene_backup_udp.SceneBackupUDP',
                 'backup_scene_follow.BackupSceneFollow', 'console_title_library.ConsoleLibraryStore',
                 'device_profiles.load_device_configuration_result', 'ableton_targets.load_target',
                 'pythonosc.udp_client.SimpleUDPClient'):
        # OSCTransport also needs SimpleUDPClient; verify host's separate m4l object instead.
        if path.endswith('SimpleUDPClient'):
            continue
        monkeypatch.setattr(path, forbidden)
    h = load_common_host()
    assert h.m4l_client is h.hot_backup is h.scene_backup_udp is h.backup_scene_follow is None
    assert h.CONSOLE_LIBRARY_STORE is None
    assert h.ableton_transport.host == '127.0.0.1'
    assert not h.ableton_transport.collect_metrics
    assert not h.DEVICE_CONFIGURATION.devices
    assert not h.APP_CAPABILITIES.console_enabled
    forbidden.assert_not_called()


def test_status_timing_and_common_go(ready):
    app, ctx = ready
    client = app.test_client()
    payload = dict(action='go', scene=1, set_generation=3, request_id='common')
    assert client.post('/action', json=payload).status_code == 200
    value = client.get('/status').json
    assert value['current_scene'] == 0 and value['prepared_scene'] == 1
    assert value['current_duration_seconds'] == value['prepared_duration_seconds'] == 60
    assert 0 <= value['current_position_seconds'] < 1
    assert client.post('/action', json=payload).status_code == 200
    assert ctx.send.call_count == 2
    assert client.post('/action', json=dict(payload, set_generation=2)).status_code == 409
    page = client.get('/').data
    assert b'light.js' in page
    assert b'remote-auth.js' not in page
    runtime = app.extensions['cl_common_light_runtime']
    assert runtime.controller.runtime.bindings.state is ctx.state
    assert runtime.controller.consumer.console is runtime.controller.consumer.backup is None


def test_navigation_stop_and_generation(ready, monkeypatch):
    app, ctx = ready
    client = app.test_client()
    for action, index in [('next', 1), ('prev', 0), ('goto', 1)]:
        response = client.post('/action', json=dict(action=action, scene=2, set_generation=3))
        assert response.status_code == 200
        assert response.json['state']['prepared_scene'] == index
    ctx.send.assert_not_called()
    h = app.extensions['cl_common_light_runtime'].host
    ctx.state['is_playing'] = True
    def query(*args, **kwargs):
        ctx.state['is_playing'] = False
        return (0,)
    monkeypatch.setattr(h, 'query', query)
    assert client.post('/action', json=dict(action='stop', set_generation=3)).status_code == 200
    assert client.get('/status').json['current_duration_seconds'] is None
    assert client.post('/action', json=dict(action='next', set_generation=2)).status_code == 409
    assert client.post('/action', json=dict(action='pause', set_generation=3)).status_code == 409


def test_manual_scene_disconnect_reconnect(ready):
    app, ctx = ready
    h = app.extensions['cl_common_light_runtime'].host
    h.ableton_runtime.update_manual_scene_state_locked(3, 1, 'Second', False)
    assert app.test_client().get('/status').json['current_scene_name'] == 'Second'
    ctx.send.assert_not_called()
    ctx.state['connected'] = False
    status = app.test_client().get('/status').json
    assert status['state'] == 'unavailable' and status['current_scene'] is None
    assert status['current_duration_seconds'] is None
    ctx.state['connected'] = True
    assert app.test_client().get('/status').json['current_scene'] == 1
    ctx.state.update(set_generation=4, set_ready=False, scenes={}, playing_scene=-1)
    assert app.test_client().get('/status').json['current_scene'] is None


@pytest.mark.parametrize('path', ['/api/hot-backup', '/api/scene-backup', '/api/ableton-discovery', '/show-info/cues', '/arrangement'])
def test_full_routes_unavailable(ready, path):
    assert ready[0].test_client().get(path).status_code == 404


def test_light_remote_toggle_controls_lan_actions(ready):
    app, ctx = ready
    client = app.test_client()

    local = dict(base_url='http://localhost')
    external = dict(
        base_url='http://light.local',
        environ_base={'REMOTE_ADDR': '192.0.2.1'},
    )

    assert client.get('/status', **external).json['remote_enabled'] is False

    payload = dict(action='next', set_generation=3)

    blocked = client.post('/action', json=payload, **external)
    assert blocked.status_code == 403
    assert blocked.json['remote_enabled'] is False
    assert blocked.json['security_required'] is False

    # Un téléphone ne peut pas ouvrir lui-même la télécommande.
    assert client.post(
        '/light/remote',
        json={'enabled': True},
        **external,
    ).status_code == 403

    enabled = client.post(
        '/light/remote',
        json={'enabled': True},
        **local,
    )
    assert enabled.status_code == 200
    assert enabled.json['remote_enabled'] is True

    # Aucun pairing/signature FULL : accès LAN direct lorsque Remote est ON.
    accepted = client.post('/action', json=payload, **external)
    assert accepted.status_code == 200
    assert accepted.json['state']['prepared_scene'] == 1

    disabled = client.post(
        '/light/remote',
        json={'enabled': False},
        **local,
    )
    assert disabled.status_code == 200
    assert disabled.json['remote_enabled'] is False

    assert client.post('/action', json=payload, **external).status_code == 403


def test_start_only_common_osc_and_refresh(ready, monkeypatch):
    app, ctx = ready
    runtime = app.extensions['cl_common_light_runtime']
    names = []
    class Thread:
        def __init__(self, *, target, name, daemon, kwargs=None):
            self.target, self.kwargs = target, kwargs or {}
            names.append(name)
        def start(self):
            if names[-1] == 'CL Light OSC':
                self.kwargs['ready_event'].set()
        def join(self, **kwargs): pass
    monkeypatch.setattr('common_light_runtime.threading.Thread', Thread)
    tls = Mock()
    monkeypatch.setattr('security_http.start_remote_tls', tls)
    for name in ('background_refresh', 'start_ltc_udp_listener', 'start_midi_expected_udp_listener',
                 'start_midi_expected_bonjour_publisher', 'refresh_arrangement_time'):
        monkeypatch.setattr(runtime.host, name, Mock(side_effect=AssertionError(name)))
    runtime.start()
    runtime.start()
    assert names == ['CL Light OSC', 'CL Light Ableton']
    tls.assert_called_once_with(app)


def test_old_new_contract_comparison(ready):
    from light_runtime import LightRuntime
    from test_local_light_runtime import FakeTransport
    app, ctx = ready
    legacy = LightRuntime(FakeTransport())
    legacy.refresh_once()
    legacy.state['set_generation'] = 3
    client = app.test_client()
    fields = ('set_available','set_generation','prepared_scene','prepared_scene_name', 'is_playing')
    def compare():
        old, new = legacy.light_state_snapshot(), client.get('/status').json
        assert {k:old[k] for k in fields} == {k:new[k] for k in fields}
    compare()
    payload = dict(action='next',set_generation=3)
    assert legacy.action(payload)[0]
    assert client.post('/action',json=payload).status_code == 200
    compare()
    # Real callback state, not a fabricated GO, follows the same observed scene.
    h = app.extensions['cl_common_light_runtime'].host
    h.ableton_runtime.update_manual_scene_state_locked(3, 0, 'First', False)
    legacy.observed_scene = 0
    legacy.state.update(playing_scene=0, is_playing=True)
    assert legacy.light_state_snapshot()['current_scene_name'] == client.get('/status').json['current_scene_name']
    legacy.unavailable()
    ctx.state['connected'] = False
    assert legacy.light_state_snapshot()['state'] == client.get('/status').json['state'] == 'unavailable'
    legacy.refresh_once()
    ctx.state.update(connected=True, set_ready=True, is_playing=False)
    assert client.get('/status').json['ableton_available'] == legacy.light_state_snapshot()['ableton_available']
    ctx.state.update(set_ready=False, set_generation=4, scenes={})
    legacy.state.update(set_ready=False, set_generation=4, scenes={})
    compare()


def test_real_refresh_failure_marks_unavailable_without_resetting_generation(ready, monkeypatch):
    app, ctx = ready
    runtime = app.extensions['cl_common_light_runtime']
    monkeypatch.setattr(runtime.host.ableton_runtime, 'refresh_names_and_transport', Mock(return_value=False))
    listener = Mock()
    monkeypatch.setattr(runtime.host.ableton_runtime, 'ensure_playing_scene_listeners', listener)
    assert not runtime.refresh_once()
    assert not runtime.snapshot()['ableton_available']
    assert runtime.snapshot()['set_generation'] == 3
    listener.assert_not_called()
    def reconnect():
        ctx.state['connected'] = True
        return True
    monkeypatch.setattr(runtime.host.ableton_runtime, 'refresh_names_and_transport', reconnect)
    assert runtime.refresh_once()
    assert runtime.snapshot()['ableton_available']
    listener.assert_called_once()
    assert app.test_client().get('/show-info').status_code == 200


def test_legacy_common_go_stop_comparison(ready, monkeypatch):
    from light_runtime import LightRuntime
    from test_local_light_runtime import FakeTransport
    app, ctx = ready
    legacy = LightRuntime(FakeTransport())
    legacy.refresh_once()
    legacy.state['set_generation'] = 3
    client = app.test_client()
    payload = dict(action='go', scene=1, set_generation=3, request_id='comparison')
    assert legacy.action(payload)[0]
    assert client.post('/action', json=payload).status_code == 200
    old, new = legacy.light_state_snapshot(), client.get('/status').json
    assert old['prepared_scene'] == new['prepared_scene'] == 1
    assert old['is_playing'] == new['is_playing']
    # Same idempotency, with common timing additionally available.
    assert legacy.action(payload)[0]
    assert client.post('/action', json=payload).status_code == 200
    assert ctx.send.call_count == 2
    h = app.extensions['cl_common_light_runtime'].host
    def stopped(*args, **kwargs):
        ctx.state['is_playing'] = False
        return (0,)
    monkeypatch.setattr(h, 'query', stopped)
    payload = dict(action='stop', set_generation=3)
    assert legacy.action(payload)[0]
    assert client.post('/action', json=payload).status_code == 200
    old, new = legacy.light_state_snapshot(), client.get('/status').json
    assert old['is_playing'] == new['is_playing'] == False
    assert old['current_scene'] is new['current_scene'] is None


def test_close_invalidates_inflight_work(ready, monkeypatch):
    app, ctx = ready
    runtime = app.extensions['cl_common_light_runtime']
    h = runtime.host
    monkeypatch.setattr(h, 'stop_playing_scene_listeners_locked', Mock())
    monkeypatch.setattr(h, '_bootstrap_transaction', None)
    runtime.close()
    assert ctx.state['set_generation'] == 4
    assert not ctx.state['set_ready']
    assert h._playing_listener_shutdown
    assert runtime.stopping.is_set()


def test_light_page_does_not_receive_full_remote_shell(ready):
    page = ready[0].test_client().get("/").get_data(as_text=True)
    assert "light.js" in page
    assert "remote-auth.js" not in page
    assert "v2-brand-subtitle" not in page
    assert "Remote professionnelle" not in page
    assert "data-arrangement-link" not in page


def test_stop_waits_for_real_ableton_confirmation(ready, monkeypatch):
    app, ctx = ready
    h = app.extensions['cl_common_light_runtime'].host
    ctx.state['is_playing'] = True
    query = Mock(side_effect=[(1,), (1,), (0,)])
    monkeypatch.setattr(h, 'query', query)
    response = app.test_client().post('/action', json=dict(action='stop', set_generation=3))
    assert response.status_code == 200
    assert query.call_count == 3
    assert not response.json['state']['is_playing']
    assert response.json['state']['current_duration_seconds'] is None


def test_stop_never_reports_success_without_confirmation(ready, monkeypatch):
    app, ctx = ready
    h = app.extensions['cl_common_light_runtime'].host
    ctx.state['is_playing'] = True
    monkeypatch.setattr(h, 'query', Mock(return_value=(1,)))
    monkeypatch.setattr('common_light_runtime.time.monotonic', Mock(side_effect=[0, 0, 1]))
    response = app.test_client().post('/action', json=dict(action='stop', set_generation=3))
    assert response.status_code == 409
    assert response.json['state']['is_playing']
    assert response.json['message'] == 'Arrêt non confirmé par Ableton'


def test_stop_rejects_set_change_while_confirming(ready, monkeypatch):
    app, ctx = ready
    h = app.extensions['cl_common_light_runtime'].host
    def changed(*args, **kwargs):
        ctx.state['set_generation'] = 4
        return (0,)
    monkeypatch.setattr(h, 'query', changed)
    response = app.test_client().post('/action', json=dict(action='stop', set_generation=3))
    assert response.status_code == 409
    assert response.json['state']['set_generation'] == 4
