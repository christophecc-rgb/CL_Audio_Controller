from unittest.mock import Mock
import ast
from pathlib import Path
from app_mode import AppMode, common_light_capabilities
from runtime_startup import create_common_light_controller
from test_local_light_go import app_module, prepare_app


def controller(monkeypatch, app):
    ctx = prepare_app(monkeypatch, app, AppMode.FULL)
    ctx.state["connected"] = True
    monkeypatch.setattr(app, 'parse_scene_duration_seconds', Mock(return_value=60))
    monkeypatch.setattr(app, 'schedule_selected_scene_duration_refresh', Mock())
    consumer = app.ProfileGoConsumer(common_light_capabilities())
    return ctx, create_common_light_controller(app.ableton_runtime, app.scene_timing, ctx, consumer)


def test_projection_and_go_share_full_state_without_services(monkeypatch, app_module):
    app = app_module
    ctx, light = controller(monkeypatch, app)
    monkeypatch.setattr(app, 'send_midi_monitor_scene_context', Mock(side_effect=AssertionError('console')))
    monkeypatch.setattr(app, 'backup_scene_follow', None)
    monkeypatch.setattr(app, 'scene_backup_udp', None)
    assert light.go('shared', 3, 1)[0]
    assert app.ableton_runtime.bindings.state is ctx.state
    assert app.ableton_runtime.snapshot()['playing_scene'] == light.snapshot()['current_scene'] == 0
    assert light.snapshot()['prepared_duration_seconds'] == 60
    assert light.snapshot()['current_duration_seconds'] == 60
    assert light.consumer.console is light.consumer.backup is None
    assert light.go('shared', 3, 1)[0]
    assert ctx.send.call_count == 2


def test_common_manual_state_and_invalidation(monkeypatch, app_module):
    app = app_module
    ctx, light = controller(monkeypatch, app)
    app.ableton_runtime.update_manual_scene_state_locked(3, 0, 'First', False)
    assert light.snapshot()['current_scene_name'] == 'First'
    assert light.snapshot()['current_position_seconds'] is not None
    ctx.state.update(set_ready=False, set_generation=4, scenes={}, playing_scene=-1)
    assert not light.snapshot()['set_available']
    assert light.snapshot()['current_scene'] is None
    assert not light.go('old', 3, 1)[0]


def test_common_module_contains_no_product_services():
    tree = ast.parse(Path('ableton_runtime.py').read_text())
    names = {n.id for n in ast.walk(tree) if isinstance(n, ast.Name)}
    assert not names & {'HotBackup', 'SceneBackupUDP', 'ConsoleGoConsumer', 'LightRuntime'}
    attributes = {n.attr for n in ast.walk(tree) if isinstance(n, ast.Attribute)}
    assert not attributes & {'record_go_midi_expectations', 'send_midi_monitor_scene_context', 'schedule_console_scene_map_refresh'}


def refresh_bindings():
    """Ready Set with no console, backup or duration worker involved."""
    import threading
    from types import SimpleNamespace
    state = dict(set_generation=7, set_ready=True, current_set_id='test.als',
                 connected=False, has_show_started=True, selected_scene=0,
                 playing_scene=-1, is_playing=False)
    bindings = SimpleNamespace(
        lock=threading.RLock(), state=state, _bootstrap_transaction=None,
        _bootstrap_generation=None, refresh_live_set_identity=Mock(return_value=7),
        start_live_set_bootstrap=Mock(), scan_playing_scene_from_tracks=Mock(),
        schedule_selected_scene_duration_refresh=Mock(),
    )
    bindings.set_connected_locked = Mock(
        side_effect=lambda value, *_: state.update(connected=value))
    bindings.query = Mock(side_effect=lambda address, **_: (0,))
    return bindings


def test_refresh_transport_response_connects_even_when_stopped():
    from ableton_runtime import refresh_names_and_transport
    bindings = refresh_bindings()
    assert refresh_names_and_transport(bindings) is True
    assert bindings.state['connected'] is True
    assert bindings.state['message'] == 'Connecté à AbletonOSC'
    bindings.query.assert_any_call('/live/song/get/is_playing', expected_generation=7)
    bindings.schedule_selected_scene_duration_refresh.assert_not_called()


def test_refresh_missing_transport_response_disconnects_without_success_fallthrough():
    from ableton_runtime import refresh_names_and_transport
    bindings = refresh_bindings()
    bindings.state['connected'] = True
    bindings.query.side_effect = lambda address, **_: (
        None if address == '/live/song/get/is_playing' else (0,))
    assert refresh_names_and_transport(bindings) is False
    assert bindings.state['connected'] is False
    assert bindings.state['message'] == 'AbletonOSC indisponible'
    assert [args.args[0] for args in bindings.set_connected_locked.call_args_list] == [False]
    bindings.scan_playing_scene_from_tracks.assert_not_called()


def test_refresh_transport_reconnects_after_timeout_on_same_runtime():
    from ableton_runtime import refresh_names_and_transport
    bindings = refresh_bindings()
    replies = iter([(0,), None, (0,)])
    bindings.query.side_effect = lambda address, **_: (
        next(replies) if address == '/live/song/get/is_playing' else (0,))
    observed = []
    for _ in range(3):
        observed.append((refresh_names_and_transport(bindings), bindings.state['connected']))
    assert observed == [(True, True), (False, False), (True, True)]
    assert bindings.state['message'] == 'Connecté à AbletonOSC'
    assert bindings.state['set_generation'] == 7
    bindings.start_live_set_bootstrap.assert_not_called()


def identity_refresh_bindings():
    from ableton_runtime import refresh_live_set_identity
    bindings = refresh_bindings()
    bindings.OSC_TIMEOUT = 0.1
    bindings._first_text_value = lambda reply: reply[0] if reply else ''
    bindings.generation_is_current = lambda generation: generation == bindings.state['set_generation']
    bindings.generation_log = Mock()
    bindings.query.side_effect = lambda address, **_: (
        ('test.als',) if address.endswith('file_path') else
        ('Test Set',) if address.endswith('/name') else (0,))
    bindings.refresh_live_set_identity = lambda generation: refresh_live_set_identity(bindings, generation)
    return bindings


def test_identity_timeout_disconnects_before_transport_probe():
    from ableton_runtime import refresh_names_and_transport
    bindings = identity_refresh_bindings()
    bindings.state['connected'] = True
    bindings.query.side_effect = lambda address, **_: None
    assert refresh_names_and_transport(bindings) is False
    assert bindings.state['connected'] is False
    assert bindings.state['message'] == 'AbletonOSC indisponible'
    assert [call.args[0] for call in bindings.query.call_args_list] == ['/live/song/get/file_path']
    assert [call.args[0] for call in bindings.set_connected_locked.call_args_list] == [False]


def test_identity_and_transport_recover_on_same_runtime():
    from ableton_runtime import refresh_names_and_transport
    bindings = identity_refresh_bindings()
    available = True
    responder = bindings.query.side_effect
    bindings.query.side_effect = lambda address, **kwargs: responder(address, **kwargs) if available else None
    assert refresh_names_and_transport(bindings) is True
    available = False
    assert refresh_names_and_transport(bindings) is False
    assert bindings.state['connected'] is False
    available = True
    assert refresh_names_and_transport(bindings) is True
    assert bindings.state['connected'] is True
    assert bindings.state['current_set_name'] == 'Test Set'


def test_stale_identity_timeout_cannot_disconnect_new_generation():
    from ableton_runtime import refresh_live_set_identity
    bindings = identity_refresh_bindings()
    bindings.state.update(connected=True, set_generation=8)
    bindings.query.side_effect = lambda address, **_: None
    assert refresh_live_set_identity(bindings, 7) is None
    assert bindings.state['connected'] is True
    bindings.set_connected_locked.assert_not_called()
