"""Light startup/API use no real Live, MIDI, network profiles or FULL services."""
from contextlib import nullcontext
import ast
import json
import os
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace
from unittest.mock import Mock, call

import pytest
from app_mode import AppMode, LOCAL_LIGHT_ACTIONS
from light_runtime import LightRuntime, create_light_app

ROOT = Path(__file__).resolve().parents[1]


class FakeTransport:
    host = '127.0.0.1'
    def __init__(self):
        self.send = Mock(return_value=True)
        self.set_unsolicited_handler = Mock()
        self.serialized_queries = Mock(side_effect=lambda **kwargs: nullcontext())
        self.query_locked = Mock(return_value=(0,))
        self.cancel_pending = Mock()
        self.responses = {
            '/live/song/get/file_path': ('/test/project.als',),
            '/live/song/get/name': ('Test',),
            '/live/song/get/scenes/name': ('First', 'Second'),
            '/live/view/get/selected_scene': (0,),
            '/live/song/get/num_tracks': (2,),
            '/live/song/get/is_playing': (0,),
        }
        self.query = Mock(side_effect=lambda address, *args, **kwargs: self.responses.get(address))
        self.serve_forever = Mock(side_effect=lambda *, bind_host, ready_event: ready_event.set())


@pytest.fixture
def runtime():
    obj = LightRuntime(FakeTransport())
    obj.refresh_once()
    return obj


@pytest.fixture
def client(runtime):
    return create_light_app(runtime).test_client()


def test_import_construction_never_starts_services(monkeypatch):
    monkeypatch.setattr('light_runtime.threading.Thread', Mock(side_effect=AssertionError('No thread at construction')))
    obj = LightRuntime(FakeTransport())
    backend = create_light_app(obj)
    assert set(backend.extensions) == {'cl_light_runtime'}
    assert obj.threads == []
    obj.transport.query.assert_not_called()


def test_only_two_local_workers_start(monkeypatch):
    obj = LightRuntime(FakeTransport())
    made = []
    class Thread:
        def __init__(self, *, target, name, daemon):
            made.append((name, daemon))
            self.target = target
            self.name = name
        def start(self):
            if self.name == 'CL Light OSC':
                self.target()
    monkeypatch.setattr('light_runtime.threading.Thread', Thread)
    obj.start()
    obj.start()
    assert made == [('CL Light OSC', True), ('CL Light Set', True)]
    obj.transport.serve_forever.assert_called_once_with(bind_host='127.0.0.1', ready_event=obj.reply_ready)


def test_exact_minimal_snapshot(client):
    response = client.get('/status')
    assert response.status_code == 200
    data = response.get_json()
    assert set(data) == {'mode', 'set_available', 'set_generation', 'current_scene',
                        'current_scene_name', 'prepared_scene', 'prepared_scene_name',
                        'next_scene', 'next_scene_name', 'is_playing', 'is_paused',
                        'allowed_actions', 'ableton_available', 'state', 'error',
                        'current_duration_seconds', 'current_position_seconds', 'current_remaining_seconds'}
    assert data['mode'] == 'LOCAL_LIGHT'
    assert data['prepared_scene_name'] == data['next_scene_name'] == 'First'
    assert data['ableton_available'] and data['set_available']
    assert data['allowed_actions'] == list(LOCAL_LIGHT_ACTIONS)


def test_go_route_and_duplicate_request(client, runtime):
    runtime.transport.send.reset_mock()
    payload = {'action': 'go', 'request_id': 'one', 'set_generation': 1, 'scene': 1}
    response = client.post('/action', json=payload)
    assert response.status_code == 200
    data = response.get_json()['state']
    assert data['current_scene'] is None
    runtime.receive('/live/track/get/playing_slot_index', 0, runtime.token, 0, source_host='127.0.0.1')
    assert runtime.light_state_snapshot()['current_scene_name'] == 'First'
    assert data['prepared_scene'] == data['next_scene'] == 1
    assert data['prepared_scene_name'] == 'Second'
    assert client.post('/action', json=payload).status_code == 200
    assert runtime.transport.send.call_args_list == [call('/live/view/set/selected_scene', 0),
                                                    call('/live/scene/fire_as_selected', 0)]


def test_navigation_only_changes_prepared_scene(client, runtime):
    runtime.transport.send.reset_mock()
    for action, index in [('next', 1), ('prev', 0), ('goto', 1)]:
        response = client.post('/action', json={'action': action, 'scene': 2})
        assert response.status_code == 200
        state = response.get_json()['state']
        assert state['prepared_scene'] == index
        assert state['current_scene'] is None
        assert not state['is_playing']
    runtime.transport.send.assert_not_called()


def test_stop_is_local_and_clears_playing(client, runtime):
    runtime.state.update(playing_scene=0, is_playing=True)
    runtime.transport.send.reset_mock()
    response = client.post('/action', json={'action': 'stop'})
    assert response.status_code == 200
    assert not response.get_json()['state']['is_playing']
    runtime.transport.send.assert_called_once_with('/live/song/stop_playing')


@pytest.mark.parametrize('path', ['/console-scene-title', '/console-library/import/cl5',
    '/api/console-simulators/status', '/api/hot-backup', '/api/scene-backup',
    '/security/status', '/security/admin/unlock', '/remote/pair', '/remote/check',
    '/api/ableton-discovery', '/network-config', '/telemetry', '/api/cl-mtc-bridge/start',
    '/show-info/builder', '/arrangement', '/shutdown'])
def test_forbidden_routes_are_not_registered(client, path):
    for method in ('get', 'post'):
        assert getattr(client, method)(path).status_code == 404


@pytest.mark.parametrize('action', ['console_title_mode', 'arrangement_start', 'xfade', 'pause', 'unknown'])
def test_only_light_actions_allowed(client, runtime, action):
    runtime.transport.send.reset_mock()
    assert client.post('/action', json={'action': action}).status_code == 403
    runtime.transport.send.assert_not_called()


@pytest.mark.parametrize('overrides,headers', [
    ({'REMOTE_ADDR': '192.168.1.2'}, {}),
    ({}, {'Host': 'Mac-Test.local'}),
    ({}, {'Origin': 'https://evil.invalid'}),
    ({}, {'Sec-Fetch-Site': 'cross-site'}),
])
def test_local_boundary_rejects_remote_and_cross_origin(client, overrides, headers):
    assert client.get('/status', environ_overrides=overrides, headers=headers).status_code == 403
    assert client.post('/action', json={'action': 'stop'}, environ_overrides=overrides, headers=headers).status_code == 403


def test_invalid_go_payload_and_old_generation(client, runtime):
    runtime.transport.send.reset_mock()
    for payload in ({'action': 'go'}, {'action': 'go', 'request_id': 'one', 'scene': 1},
                    {'action': 'go', 'request_id': '', 'set_generation': 1, 'scene': 1}):
        assert client.post('/action', json=payload).status_code == 400
    assert client.post('/action', json={'action': 'go', 'request_id': 'old', 'set_generation': 0, 'scene': 1}).status_code == 409
    runtime.transport.send.assert_not_called()


def test_absent_ableton_has_no_console_dependency():
    obj = LightRuntime(FakeTransport())
    obj.transport.responses['/live/song/get/file_path'] = None
    obj.refresh_once()
    data = create_light_app(obj).test_client().get('/status').get_json()
    assert not data['ableton_available'] and not data['set_available']
    assert data['error'] == 'Ableton indisponible'
    assert not data['allowed_actions']


def test_refresh_never_queries_duration_arrangement_or_console(runtime):
    runtime.refresh_once()
    addresses = {item.args[0] for item in runtime.transport.query.call_args_list}
    assert addresses == {'/live/song/get/file_path', '/live/song/get/name',
                         '/live/song/get/scenes/name', '/live/view/get/selected_scene',
                         '/live/song/get/num_tracks', '/live/song/get/is_playing'}
    assert all('playing_slot_index' in item.args[0] for item in runtime.transport.send.call_args_list)


def test_track_event_updates_current_without_timecode(runtime):
    runtime.receive('/live/track/get/playing_slot_index', 0, runtime.token, 0, source_host='127.0.0.1')
    snapshot = runtime.light_state_snapshot()
    assert snapshot['current_scene_name'] == 'First'
    assert snapshot['prepared_scene_name'] == 'Second'
    runtime.receive('/live/track/get/playing_slot_index', 0, runtime.token, 1, source_host='192.168.1.2')
    assert runtime.light_state_snapshot()['current_scene_name'] == 'First'


def test_set_change_and_old_subscription_are_rejected(runtime):
    old_token = runtime.token
    runtime.completed_go_requests[(1, 'old')] = {'ok': True, 'message': 'old'}
    runtime.transport.responses['/live/song/get/file_path'] = ('/test/other.als',)
    runtime.refresh_once()
    assert runtime.state['set_generation'] == 2
    assert not runtime.completed_go_requests
    runtime.receive('/live/track/get/playing_slot_index', 0, old_token, 1, source_host='127.0.0.1')
    assert runtime.light_state_snapshot()['current_scene'] is None


def test_send_failure_is_not_reported_as_success(client, runtime):
    runtime.transport.send.side_effect = lambda address, *args: address != '/live/scene/fire_as_selected'
    response = client.post('/action', json={'action': 'go', 'request_id': 'bad-send', 'set_generation': 1, 'scene': 1})
    assert response.status_code == 503
    assert not response.get_json()['ok']


def test_startup_factory_and_entrypoints_do_not_import_full_modules():
    script = r'''
import sys, importlib.abc, runpy, types
blocked = {'app', 'launcher_control', 'remote_security', 'security_http', 'remote_tls',
           'hot_backup_sync', 'scene_backup_udp', 'backup_scene_follow', 'ableton_discovery',
           'bonjour_remote', 'console_title_library', 'device_profiles', 'ltc_receiver',
           'midi_endpoint_names'}
class Guard(importlib.abc.MetaPathFinder):
 def find_spec(self, fullname, *args):
  if fullname in blocked: raise AssertionError('Forbidden import: '+fullname)
sys.meta_path.insert(0, Guard())
from runtime_startup import create_selected_app
from app_mode import capabilities_for, AppMode
assert capabilities_for().mode is AppMode.LOCAL_LIGHT
app = create_selected_app()
assert app.test_client().get('/status').status_code == 200
assert set(app.extensions) == {'cl_light_runtime'}
import light_runtime
calls = []
light_runtime.run_light = lambda **kw: calls.append(kw)
for entry in ('app.py', 'launcher_control.py'):
 try: runpy.run_path(entry, run_name='__main__')
 except SystemExit as e: assert e.code == 0
assert calls == [{'window':False}, {'window':True}]
assert not blocked.intersection(sys.modules)
'''
    env = dict(os.environ, CL_APP_MODE='LOCAL_LIGHT', CL_LIGHT_ENGINE='legacy', PYTHONDONTWRITEBYTECODE='1')
    result = subprocess.run([sys.executable, '-c', script], cwd=ROOT, env=env,
                            text=True, capture_output=True, timeout=10)
    assert result.returncode == 0, result.stderr


def test_full_entry_guard_has_no_runtime_effect(monkeypatch):
    import runtime_startup
    monkeypatch.setattr(runtime_startup, 'capabilities_for', lambda: SimpleNamespace(mode=AppMode.FULL))
    monkeypatch.setattr('light_runtime.run_light', Mock(side_effect=AssertionError('FULL must not load Light')))
    assert runtime_startup.run_light_entry('backend') is False
    assert runtime_startup.run_light_entry('launcher') is False


def test_full_startup_and_routes_source_unchanged_by_early_guard():
    # Both original FULL startup blocks still contain their complete service list.
    source = (ROOT / 'app.py').read_text()
    for name in ('start_ltc_udp_listener', 'start_midi_expected_udp_listener',
                 'start_midi_expected_bonjour_publisher', 'start_remote_tls'):
        assert name in source[source.rfind('if __name__ == "__main__":'):]
    source = (ROOT / 'launcher_control.py').read_text()
    assert '"start_ltc_udp_listener"' in source
    assert 'ensure_midi_console_monitor()' in source
    assert '_cl_mtc_bridge_autostart()' in source


def test_inconsistent_set_is_not_published():
    obj = LightRuntime(FakeTransport())
    paths = iter([('/test/first.als',), ('/test/changed.als',)])
    ordinary = obj.transport.query.side_effect
    obj.transport.query.side_effect = lambda address, *args, **kwargs: (
        next(paths) if address == '/live/song/get/file_path' else ordinary(address, *args, **kwargs))
    obj.refresh_once()
    assert not obj.state['set_ready']
    obj.transport.send.assert_not_called()


def test_startup_during_bootstrap_does_not_publish_old_generation():
    obj = LightRuntime(FakeTransport())
    ordinary = obj.transport.query.side_effect
    def query(address, *args, **kwargs):
        if address == '/live/song/get/scenes/name':
            obj.receive('/live/startup', source_host='127.0.0.1')
        return ordinary(address, *args, **kwargs)
    obj.transport.query.side_effect = query
    obj.refresh_once()
    assert not obj.state['set_ready']
    obj.transport.send.assert_not_called()


def test_factory_uses_loopback_and_disables_metrics(monkeypatch):
    transport = FakeTransport()
    factory = Mock(return_value=transport)
    monkeypatch.setattr('light_runtime.OSCTransport', factory)
    LightRuntime()
    factory.assert_called_once_with(host='127.0.0.1', send_port=11000, reply_port=11001, collect_metrics=False)


def test_selected_backend_cannot_be_remote():
    transport = FakeTransport()
    transport.host = '192.168.1.2'
    with pytest.raises(ValueError, match='loopback'):
        LightRuntime(transport)


def test_reply_port_failure_does_not_start_refresh(monkeypatch):
    obj = LightRuntime(FakeTransport())
    obj.reply_ready = Mock(wait=Mock(return_value=False))
    made = []
    def factory(**kwargs):
        made.append(kwargs['name'])
        return Mock()
    monkeypatch.setattr('light_runtime.threading.Thread', factory)
    with pytest.raises(RuntimeError, match='OSC'):
        obj.start()
    assert made == ['CL Light OSC']


def test_bypass_of_light_factory_fails_before_full_initialization():
    script = '''
import importlib
for name in ('app', 'launcher_control'):
 try: importlib.import_module(name)
 except RuntimeError as e: assert 'create_selected_app' in str(e)
 else: raise AssertionError('FULL runtime initialized in Light')
import sys
assert not {'remote_security','remote_tls','hot_backup_sync','ableton_discovery'}.intersection(sys.modules)
'''
    env = dict(os.environ, CL_APP_MODE='LOCAL_LIGHT', CL_LIGHT_ENGINE='legacy', PYTHONDONTWRITEBYTECODE='1')
    result = subprocess.run([sys.executable, '-c', script], cwd=ROOT, env=env,
                            capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr


def test_http_listener_is_loopback_before_services(monkeypatch):
    import light_runtime
    order = []
    runtime = SimpleNamespace(start=lambda: order.append('start'), close=lambda: order.append('close'))
    backend = SimpleNamespace(extensions={'cl_light_runtime': runtime})
    server = SimpleNamespace(serve_forever=lambda: order.append('serve'),
                             server_close=lambda: order.append('server_close'))
    monkeypatch.setattr(light_runtime, 'create_light_app', lambda: backend)
    def make_server(host, port, app, *, threaded):
        assert host == '127.0.0.1' and port == 5050 and threaded
        order.append('bind')
        return server
    monkeypatch.setattr('werkzeug.serving.make_server', make_server)
    light_runtime.run_light()
    assert order == ['bind', 'start', 'serve', 'server_close', 'close']


def test_http_port_conflict_never_starts_or_adopts_other_server(monkeypatch):
    import light_runtime
    start = Mock()
    runtime = SimpleNamespace(start=start)
    monkeypatch.setattr(light_runtime, 'create_light_app', lambda: SimpleNamespace(extensions={'cl_light_runtime': runtime}))
    monkeypatch.setattr('werkzeug.serving.make_server', Mock(side_effect=OSError('occupied')))
    with pytest.raises(OSError):
        light_runtime.run_light()
    start.assert_not_called()


def test_scene_order_change_invalidates_old_go_generation(runtime):
    runtime.transport.responses['/live/song/get/scenes/name'] = ('Second', 'First')
    runtime.refresh_once()
    assert runtime.state['set_generation'] == 2
    assert runtime.light_state_snapshot()['prepared_scene_name'] == 'Second'
    runtime.transport.send.reset_mock()
    ok, message, code = runtime.go({'request_id': 'old-scene-order', 'set_generation': 1, 'scene': 1})
    assert not ok and code == 409
    runtime.transport.send.assert_not_called()


def test_static_methods_and_non_json_are_restricted(client):
    assert client.get('/static/remote-auth.js').status_code == 200
    assert client.post('/static/remote-auth.js').status_code == 405
    assert client.post('/status').status_code == 405
    assert client.post('/action', json=[]).status_code == 400
    assert client.post('/action', data='not-json').status_code == 400


def test_transport_metrics_are_off_without_changing_default():
    from osc_transport import OSCTransport
    light = OSCTransport(collect_metrics=False)
    full = OSCTransport()
    assert full.collect_metrics is True
    for transport in (light, full):
        transport._client = Mock()
        transport._osc_payload_size = Mock(return_value=12)
    light.send('/live/song/stop_playing')
    light._receive_datagram(('127.0.0.1', 11000), '/live/song/get/is_playing', 0)
    assert light._traffic_tx_messages_total == light._traffic_rx_messages_total == 0
    light._osc_payload_size.assert_not_called()
    full.send('/live/song/stop_playing')
    assert full._traffic_tx_messages_total == 1
    full._osc_payload_size.assert_called_once()


def test_refresh_preserves_explicit_preparation_before_first_go(runtime):
    assert runtime.action({'action': 'next'})[0]
    runtime.refresh_once()
    assert runtime.state['selected_scene'] == 1
    assert runtime.light_state_snapshot()['prepared_scene'] == 1


def test_go_defaults_to_prepared_scene_and_waits_for_real_event(runtime):
    assert runtime.action({'action': 'next'})[0]
    runtime.transport.query_locked.return_value = (1,)
    assert runtime.action({'action': 'go', 'request_id': 'prepared', 'set_generation': 1})[0]
    runtime.transport.send.assert_any_call('/live/scene/fire_as_selected', 1)
    assert runtime.light_state_snapshot()['current_scene'] is None
    runtime.receive('/live/track/get/playing_slot_index', 0, runtime.token, 1, source_host='127.0.0.1')
    assert runtime.light_state_snapshot()['current_scene'] == 1


def test_real_ableton_scene_names_address(runtime):
    runtime.transport.query.assert_any_call('/live/song/get/scenes/name', timeout=.2)
    assert '/live/song/get/scene_names' not in [c.args[0] for c in runtime.transport.query.call_args_list]


def test_dedicated_light_interface(client):
    response = client.get('/')
    assert response.status_code == 200
    html = response.get_data(as_text=True)
    for expected in ('light.css', 'light.js', 'SCÈNE EN COURS', 'SCÈNE PRÉPARÉE', 'data-action="go"', 'data-action="prev"', 'data-action="next"', 'data-action="stop"'):
        assert expected in html
    for forbidden in ('ltc', 'timecode', 'mtc', 'console', 'program change', 'expected', 'returned', 'foh', 'rtp', 'bonjour', 'pairing', 'tls', 'backup', 'arrangement', 'remote.js'):
        assert forbidden not in html.lower()
    for asset in ('light.css', 'light.js'):
        assert client.get('/static/' + asset).status_code == 200


def test_full_home_route_unchanged():
    # Light has a separate factory; FULL keeps its existing remote template.
    source = (ROOT / 'app.py').read_text()
    assert 'render_template("index.html"' in source or "render_template('index.html'" in source


def timing_clip(runtime, **overrides):
    """Fake a valid SAISON 8 timing branch.

    0 = SAISON 8 group
    1 = active JMD branch
    2 = active audio leaf playing scene 0
    """
    values = dict(
        is_audio_clip=1,
        warping=0,
        looping=0,
        is_recording=0,
        start_marker=10,
        end_marker=208,
        playing_position=112,
    )
    values.update(overrides)

    tracks = {
        0: dict(
            name='15 SAISON 8',
            is_foldable=True,
            is_grouped=False,
            mute=False,
            playing_slot_index=-1,
        ),
        1: dict(
            name='16 JMD',
            is_foldable=True,
            is_grouped=True,
            mute=False,
            playing_slot_index=-1,
        ),
        2: dict(
            name='JOHANNA/MIKA/DIR',
            is_foldable=False,
            is_grouped=True,
            mute=False,
            playing_slot_index=0,
        ),
    }

    # The shared runtime fixture was bootstrapped with FakeTransport's
    # default two tracks. This timing fixture models a third leaf track,
    # so extend the subscribed slot map before delivering its event.
    runtime.slots[2] = None

    runtime.receive(
        '/live/track/get/playing_slot_index',
        2, runtime.token, 0,
        source_host='127.0.0.1',
    )

    def response(address, *args, **kwargs):
        if address == '/live/song/get/num_tracks':
            return (3,)

        if address.startswith('/live/track/get/'):
            prop = address.rsplit('/', 1)[-1]
            track = args[0]

            if track not in tracks or prop not in tracks[track]:
                return None

            return (track, tracks[track][prop])

        if address.startswith('/live/clip/get/'):
            prop = address.rsplit('/', 1)[-1]
            track, scene = args

            if track != 2 or scene != 0:
                return None

            if prop not in values:
                return None

            return (track, scene, values[prop])

        return None

    runtime.transport.query.side_effect = response


def test_current_clip_exact_seconds(runtime):
    timing_clip(runtime)
    runtime.refresh_current_timing()
    data = runtime.light_state_snapshot()
    assert [data[k] for k in ('current_duration_seconds', 'current_position_seconds', 'current_remaining_seconds')] == [198, 102, 96]
    assert all(
        c.args[1:] == (2, 0)
        for c in runtime.transport.query.call_args_list
        if '/live/clip/' in c.args[0]
    )


@pytest.mark.parametrize(
    'invalid',
    [
        dict(warping=1),
        dict(is_audio_clip=0),
        dict(looping=1),
        dict(is_recording=1),
        dict(end_marker=None),
        dict(playing_position=float('nan')),
    ],
)
def test_timing_unavailable_never_blocks_go_or_connection(runtime, invalid):
    timing_clip(runtime, **invalid)
    runtime.refresh_current_timing()
    assert runtime.light_state_snapshot()['current_duration_seconds'] is None
    assert runtime.light_state_snapshot()['ableton_available']
    runtime.transport.query_locked.return_value = (1,)
    assert runtime.go(dict(request_id='no-duration', set_generation=runtime.state['set_generation'], scene=2))[0]


def test_timing_cleared_scene_stop_disconnect_and_set(runtime):
    timing_clip(runtime)
    runtime.refresh_current_timing()
    runtime.receive('/live/track/get/playing_slot_index', 0, runtime.token, 1, source_host='127.0.0.1')
    assert runtime.light_state_snapshot()['current_duration_seconds'] is None
    timing_clip(runtime)
    runtime.refresh_current_timing()
    runtime.action({'action': 'stop'})
    assert runtime.light_state_snapshot()['current_position_seconds'] is None
    timing_clip(runtime)
    runtime.refresh_current_timing()
    runtime.unavailable()
    assert runtime.light_state_snapshot()['current_remaining_seconds'] is None
    runtime.invalidate()
    assert runtime.light_state_snapshot()['current_duration_seconds'] is None


def test_timing_generation_change_during_response_ignored(runtime):
    timing_clip(runtime)
    original = runtime.transport.query.side_effect
    def change(address, *args, **kwargs):
        response = original(address, *args, **kwargs)
        if address.endswith('/playing_position'):
            runtime.invalidate()
        return response
    runtime.transport.query.side_effect = change
    runtime.refresh_current_timing()
    assert runtime.light_state_snapshot()['current_duration_seconds'] is None

def test_duplicate_track_event_same_scene_preserves_manual_preparation(runtime):
    # First track establishes scene 0 as the scene really playing.
    runtime.receive(
        '/live/track/get/playing_slot_index',
        0, runtime.token, 0,
        source_host='127.0.0.1',
    )
    assert runtime.light_state_snapshot()['prepared_scene'] == 1

    # Operator deliberately moves preparation back to scene 0.
    assert runtime.action({'action': 'prev'})[0]
    assert runtime.light_state_snapshot()['prepared_scene'] == 0
    assert runtime.prepared_by_navigation

    # Another track reports the SAME playing scene. This used to erase PREV
    # and put preparation back on scene 1.
    runtime.receive(
        '/live/track/get/playing_slot_index',
        1, runtime.token, 0,
        source_host='127.0.0.1',
    )

    snapshot = runtime.light_state_snapshot()
    assert snapshot['current_scene'] == 0
    assert snapshot['prepared_scene'] == 0
    assert runtime.prepared_by_navigation


def test_new_playing_scene_resumes_automatic_preparation(runtime):
    runtime.state['scenes'][2] = 'Third'

    runtime.receive(
        '/live/track/get/playing_slot_index',
        0, runtime.token, 0,
        source_host='127.0.0.1',
    )

    # Explicit operator preparation must survive duplicate events...
    assert runtime.action({'action': 'prev'})[0]
    assert runtime.light_state_snapshot()['prepared_scene'] == 0

    # ...but a genuinely different scene launched in Live becomes current
    # and automatically prepares the following scene.
    runtime.receive(
        '/live/track/get/playing_slot_index',
        1, runtime.token, 1,
        source_host='127.0.0.1',
    )

    snapshot = runtime.light_state_snapshot()
    assert snapshot['current_scene'] == 1
    assert snapshot['prepared_scene'] == 2
    assert snapshot['prepared_scene_name'] == 'Third'
    assert not runtime.prepared_by_navigation
