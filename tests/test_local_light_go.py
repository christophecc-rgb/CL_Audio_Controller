"""Product capabilities and shared GO, with no real sockets or Live commands."""
from contextlib import nullcontext
from dataclasses import FrozenInstanceError
from unittest.mock import Mock, call
import threading

import pytest
from app_mode import AppMode, capabilities_for, local_light_state
from go_core import GoContext, LocalGoConsumer, execute_go_core


def context():
    state = {'set_ready': True, 'set_generation': 3, 'scenes': {0: 'First', 1: 'Second'},
             'selected_scene': 0, 'next_scene': 0, 'is_playing': False, 'is_paused': False}
    return GoContext(
        state, threading.RLock(), threading.Lock(), {},
        Mock(serialized_queries=Mock(side_effect=lambda *, priority: nullcontext())),
        lambda n: int(n) - 1 if int(n) > 0 else None,
        lambda n: state['set_generation'] == n, Mock(), Mock(return_value=(0,)), Mock(),
    )


def test_capabilities_default_full_and_light_are_immutable():
    assert capabilities_for().mode is AppMode.FULL
    full = capabilities_for('FULL')
    light = capabilities_for('LOCAL_LIGHT')
    assert full.console_enabled and full.hot_backup_enabled and full.duration_enabled
    assert light.showcue_enabled and light.builder_enabled and light.ableton_local_enabled and light.go_enabled
    for field in ('console_enabled', 'program_change_enabled', 'ltc_enabled', 'mtc_enabled',
                  'remote_enabled', 'hot_backup_enabled', 'network_discovery_enabled',
                  'console_feedback_enabled', 'duration_enabled'):
        assert getattr(light, field) is False
    with pytest.raises(FrozenInstanceError):
        light.ltc_enabled = True
    with pytest.raises(ValueError):
        capabilities_for('invalid')


def test_light_go_needs_only_local_transport_and_prepares_next():
    ctx = context()
    assert execute_go_core(ctx, LocalGoConsumer(), 'one', 3, 1) == (True, 'Scène 1 lancée')
    assert ctx.send.call_args_list == [call('/live/view/set/selected_scene', 0),
                                      call('/live/scene/fire_as_selected', 0)]
    ctx.ableton_transport.serialized_queries.assert_called_once_with(priority=True)
    snapshot = local_light_state(ctx.state)
    assert snapshot == {
        'set_available': True, 'set_generation': 3, 'current_scene': 0,
        'current_scene_name': 'First', 'prepared_scene': 1,
        'prepared_scene_name': 'Second', 'next_scene': 1,
        'is_playing': True, 'is_paused': False,
        'allowed_actions': ['go', 'prev', 'next', 'goto', 'stop', 'pause'], 'state': 'playing',
    }
    assert not any(key.startswith(('ltc', 'mtc', 'expected', 'console', 'scene_duration', 'playback_deadline'))
                   for key in ctx.state)


def test_last_scene_stays_prepared_without_out_of_bounds():
    ctx = context()
    ctx._query_with_query_lock_held.return_value = (1,)
    assert execute_go_core(ctx, LocalGoConsumer(), 'last', 3, 2)[0]
    assert ctx.state['next_scene'] == ctx.state['selected_scene'] == 1


def test_duplicate_id_does_not_repeat_launch_or_consumers():
    ctx = context()
    consumer = Mock()
    first = execute_go_core(ctx, consumer, 'same', 3, 1)
    second = execute_go_core(ctx, consumer, 'same', 3, 1)
    assert first == second
    assert ctx.send.call_count == 2
    consumer.before_launch.assert_called_once()
    consumer.after_commit.assert_called_once()


@pytest.mark.parametrize('generation,scene,ready', [(2, 1, True), (3, 9, True), (3, 0, True), (3, 1, False)])
def test_invalid_go_never_sends_or_notifies(generation, scene, ready):
    ctx = context()
    ctx.state['set_ready'] = ready
    consumer = Mock()
    assert not execute_go_core(ctx, consumer, 'invalid', generation, scene)[0]
    ctx.send.assert_not_called()
    assert not consumer.mock_calls
    assert not ctx.completed_go_requests


def test_set_changed_during_confirmation_prevents_fire():
    ctx = context()
    def confirm(*args, **kwargs):
        ctx.state['set_generation'] = 4
        return (0,)
    ctx._query_with_query_lock_held.side_effect = confirm
    consumer = Mock()
    assert not execute_go_core(ctx, consumer, 'race', 3, 1)[0]
    assert ctx.send.call_args_list == [call('/live/view/set/selected_scene', 0)]
    assert not consumer.mock_calls


def test_reordered_confirmation_is_retried_before_fire():
    ctx = context()
    ctx._query_with_query_lock_held.side_effect = [(1,), (0,)]
    assert execute_go_core(ctx, LocalGoConsumer(), 'reorder', 3, 1)[0]
    assert ctx._query_with_query_lock_held.call_count == 2
    assert ctx.send.call_args_list[-1] == call('/live/scene/fire_as_selected', 0)


def test_snapshot_is_pure_and_clears_unavailable_scene_metadata():
    ctx = context()
    ctx.state.update(set_ready=False, playing_scene=0, selected_scene=1, is_playing=True,
                     ltc_timecode='01:00:00:00', midi_console=object())
    before = dict(ctx.state)
    result = local_light_state(ctx.state)
    assert ctx.state == before
    assert result['current_scene'] is result['prepared_scene'] is None
    assert result['current_scene_name'] == result['prepared_scene_name'] == ''
    assert not result['allowed_actions'] and not result['is_playing']
    assert 'ltc_timecode' not in result and 'midi_console' not in result


@pytest.fixture
def app_module():
    # Same isolated loader as the existing generation tests; no service startup.
    from test_live_set_generation import load_app_module
    return load_app_module()


def prepare_app(monkeypatch, app, mode):
    ctx = context()
    for name in ('state', 'lock', 'scene_transaction_lock', 'completed_go_requests',
                 'ableton_transport', 'clamp_scene_number', 'generation_is_current',
                 'send', '_query_with_query_lock_held', 'write_keyboard_diagnostic'):
        monkeypatch.setattr(app, name, getattr(ctx, name))
    monkeypatch.setattr(app, 'APP_CAPABILITIES', capabilities_for(mode))
    return ctx


def test_app_light_does_not_access_full_consumers(monkeypatch, app_module):
    app = app_module
    ctx = prepare_app(monkeypatch, app, AppMode.LOCAL_LIGHT)
    forbidden = ('send_midi_monitor_scene_context', 'record_go_midi_expectations',
                 'copy_to_backup', 'parse_scene_duration_seconds',
                 'resolve_scene_clip_duration_async', 'schedule_selected_scene_duration_refresh')
    mocks = []
    for name in forbidden:
        mock = Mock(side_effect=AssertionError('Forbidden Light consumer: ' + name))
        monkeypatch.setattr(app, name, mock)
        mocks.append(mock)
    monkeypatch.setattr(app, 'backup_scene_follow', None)
    monkeypatch.setattr(app, 'scene_backup_udp', None)
    monkeypatch.setattr(app, 'hot_backup', None)
    monkeypatch.setattr(app.threading, 'Thread', Mock(side_effect=AssertionError('No duration thread')))
    assert app.execute_go_transaction('light', 3, 1)[0]
    assert app.local_light_state_snapshot()['prepared_scene'] == 1
    for mock in mocks:
        mock.assert_not_called()


def test_full_consumers_keep_historical_order_and_state(monkeypatch, app_module):
    app = app_module
    ctx = prepare_app(monkeypatch, app, AppMode.FULL)
    trace = []
    ctx.send.side_effect = lambda address, *args: trace.append((address, args))
    def recorder(name):
        return Mock(side_effect=lambda *args: trace.append((name, args)))
    for name in ('send_midi_monitor_scene_context', 'record_go_midi_expectations',
                 'copy_to_backup', 'schedule_selected_scene_duration_refresh'):
        monkeypatch.setattr(app, name, recorder(name))
    monkeypatch.setattr(app, 'backup_scene_follow', Mock(note_cl_launch=recorder('note_cl_launch')))
    monkeypatch.setattr(app, 'scene_backup_udp', Mock(scene_launched=recorder('scene_launched')))
    monkeypatch.setattr(app, 'parse_scene_duration_seconds', Mock(return_value=10))
    assert app.execute_go_transaction('full', 3, 1)[0]
    timestamp = ctx.state['expected_activated_at']
    assert trace == [
        ('/live/view/set/selected_scene', (0,)),
        ('send_midi_monitor_scene_context', (3, 0, 'First')),
        ('record_go_midi_expectations', (0, timestamp)),
        ('note_cl_launch', (0,)), ('/live/scene/fire_as_selected', (0,)),
        ('scene_launched', (1,)), ('copy_to_backup', ('/live/scene/fire', 0)),
        ('send_midi_monitor_scene_context', (3, 0, 'First')),
        ('schedule_selected_scene_duration_refresh', (1, 3)),
    ]
    assert ctx.state['expected_scene_signature'] == (3, 'session', 0)
    assert ctx.state['scene_duration_seconds'] == ctx.state['remaining_seconds'] == 10
    assert ctx.state['playback_deadline'] == timestamp + 10
    assert ctx.state['selected_scene_duration_seconds'] == 10
    assert ctx.state['selected_scene_duration_index'] == 1
    assert ctx.state['sync_source'] == 'Télécommande'
    assert ctx.state['arrangement_marker'] == '—'


def test_route_keeps_missing_request_and_generation_protection(monkeypatch, app_module):
    app = app_module
    prepare_app(monkeypatch, app, AppMode.LOCAL_LIGHT)
    client = app.app.test_client()
    for payload in ({'action': 'go', 'scene': 1, 'set_generation': 3},
                    {'action': 'go', 'scene': 1, 'request_id': 'one'}):
        response = client.post('/action', json=payload)
        assert response.status_code == 400
    app.send.assert_not_called()


def test_full_missing_duration_keeps_async_resolution_and_backup_isolation(monkeypatch, app_module):
    app = app_module
    ctx = prepare_app(monkeypatch, app, AppMode.FULL)
    monkeypatch.setattr(app, 'parse_scene_duration_seconds', Mock(return_value=None))
    monkeypatch.setattr(app, 'send_midi_monitor_scene_context', Mock())
    monkeypatch.setattr(app, 'record_go_midi_expectations', Mock())
    monkeypatch.setattr(app, 'copy_to_backup', Mock())
    monkeypatch.setattr(app, 'backup_scene_follow', Mock())
    monkeypatch.setattr(app, 'scene_backup_udp', Mock(scene_launched=Mock(side_effect=RuntimeError('offline'))))
    monkeypatch.setattr(app, 'schedule_selected_scene_duration_refresh', Mock())
    thread = Mock()
    factory = Mock(return_value=thread)
    monkeypatch.setattr(app.threading, 'Thread', factory)
    assert app.execute_go_transaction('full-duration', 3, 1)[0]
    factory.assert_called_once_with(
        target=app.resolve_scene_clip_duration_async,
        args=(0, 3, ctx.state['expected_activated_at']), daemon=True)
    thread.start.assert_called_once_with()
    assert app.send_midi_monitor_scene_context.call_count == 2
    app.copy_to_backup.assert_called_once_with('/live/scene/fire', 0)
    assert ctx.state['playback_deadline'] is None


def test_confirmation_timeout_never_fires_or_prepares(monkeypatch):
    import go_core
    ctx = context()
    ctx._query_with_query_lock_held.return_value = (1,)
    before = dict(ctx.state)
    ticks = iter((0, 0, 0, 0, 1))
    monkeypatch.setattr(go_core.time, 'monotonic', lambda: next(ticks))
    consumer = Mock()
    ok, message = execute_go_core(ctx, consumer, 'timeout', 3, 1)
    assert not ok and 'non confirmée' in message
    assert ctx.state == before
    assert not consumer.mock_calls
    assert ctx.send.call_args_list == [call('/live/view/set/selected_scene', 0)]


def test_concurrent_duplicate_id_fires_once():
    ctx = context()
    results = []
    barrier = threading.Barrier(2)
    def go():
        barrier.wait(timeout=2)
        results.append(execute_go_core(ctx, LocalGoConsumer(), 'concurrent', 3, 1))
    threads = [threading.Thread(target=go) for _ in range(2)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=2)
        assert not thread.is_alive()
    assert len(results) == 2 and all(result[0] for result in results)
    assert ctx.send.call_args_list.count(call('/live/scene/fire_as_selected', 0)) == 1


def test_future_light_timing_consumer_excludes_console_and_backup(monkeypatch, app_module):
    from app_mode import common_light_capabilities
    app = app_module
    ctx = prepare_app(monkeypatch, app, AppMode.FULL)
    forbidden = Mock(side_effect=AssertionError('Console/backup invoked'))
    for name in ('send_midi_monitor_scene_context', 'record_go_midi_expectations', 'copy_to_backup'):
        monkeypatch.setattr(app, name, forbidden)
    monkeypatch.setattr(app, 'backup_scene_follow', None)
    monkeypatch.setattr(app, 'scene_backup_udp', None)
    monkeypatch.setattr(app, 'parse_scene_duration_seconds', Mock(return_value=42))
    prepare = Mock()
    monkeypatch.setattr(app, 'schedule_selected_scene_duration_refresh', prepare)
    consumer = app.ProfileGoConsumer(common_light_capabilities())
    assert consumer.console is consumer.backup is None
    assert execute_go_core(ctx, consumer, 'timing-only', 3, 1)[0]
    assert ctx.state['scene_duration_seconds'] == 42
    prepare.assert_called_once_with(1, 3)
    forbidden.assert_not_called()


def test_full_manual_event_keeps_console_order_and_timing(monkeypatch, app_module):
    app = app_module
    ctx = prepare_app(monkeypatch, app, AppMode.FULL)
    ctx.state['scenes'] = {0: 'First 01:00', 1: 'Second 02:00'}
    monkeypatch.setattr(app, '_playing_listener_generation', 3)
    monkeypatch.setattr(app, '_playing_listener_token', 'token')
    monkeypatch.setattr(app, '_playing_listener_tracks', {0: -1})
    trace = []
    for name in ('record_go_midi_expectations', 'send_midi_monitor_scene_context',
                 'schedule_selected_scene_duration_refresh'):
        monkeypatch.setattr(app, name, Mock(side_effect=lambda *a, _n=name, **k: trace.append((_n, a, k))))
    app.receive_playing_slot_event((0, 'token', 0))
    assert [v[0] for v in trace] == ['record_go_midi_expectations',
        'send_midi_monitor_scene_context', 'schedule_selected_scene_duration_refresh']
    assert trace[0][2] == {'source': 'ableton_playing_scene_event'}
    assert ctx.state['playing_scene'] == 0 and ctx.state['selected_scene'] == 1
    assert ctx.state['scene_duration_seconds'] == 60
    assert ctx.state['selected_scene_duration_seconds'] == 120
    assert ctx.state['remaining_seconds'] == 60
    assert ctx.state['playback_deadline'] == ctx.state['expected_activated_at'] + 60
    ctx.send.assert_not_called()
    before = list(trace)
    app.receive_playing_slot_event((0, 'token', 0))
    assert trace == before


def test_timing_api_sources_are_explicit_and_adapter_is_lazy():
    from scene_timing import SceneTimingAPI, TimingSource
    callback = Mock()
    api = SceneTimingAPI(callback, callback, callback, callback)
    callback.assert_not_called()
    api.refresh_remaining()
    callback.assert_called_once_with()
    assert {s.value for s in TimingSource} == {'declared', 'clip_estimated', 'observed'}


def test_manual_scene_timing_boundary_has_no_console_or_backup_io(monkeypatch, app_module):
    app = app_module
    ctx = prepare_app(monkeypatch, app, AppMode.FULL)
    for name in ('record_go_midi_expectations', 'send_midi_monitor_scene_context', 'copy_to_backup'):
        monkeypatch.setattr(app, name, Mock(side_effect=AssertionError('External effect')))
    now = app.update_manual_scene_state_locked(3, 0, 'First 01:00', False)
    assert ctx.state['playing_scene'] == 0
    assert ctx.state['scene_duration_seconds'] == 60
    assert ctx.state['playback_deadline'] == now + 60
    ctx.send.assert_not_called()
