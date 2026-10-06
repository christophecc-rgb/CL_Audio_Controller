from backup_scene_follow import BackupSceneFollow


def observer():
    follow = BackupSceneFollow(clock=lambda: 100)
    follow.reset('session-token', (0, 1))
    follow.receive(0, 'session-token', 0)
    follow.receive(1, 'session-token', 0)
    return follow


def test_direct_launch_and_same_scene_relaunch():
    follow = observer()
    assert follow.receive(0, 'session-token', 1)
    assert not follow.receive(0, 'session-token', 1)
    assert not follow.receive(0, 'session-token', 0)
    assert follow.receive(0, 'session-token', 1)


def test_cl_confirmation_is_not_a_second_launch():
    follow = observer()
    follow.note_cl_launch(0)
    assert not follow.receive(0, 'session-token', 1)
    follow.receive(0, 'session-token', 0)
    assert follow.receive(0, 'session-token', 1)


def test_initial_snapshot_and_old_callbacks_never_launch():
    follow = BackupSceneFollow()
    follow.reset('new', (0,))
    assert not follow.receive(0, 'new', 1)
    assert not follow.receive(0, 'old', 0)
    assert not follow.receive(0, 'old', 1)
    assert not follow.receive(5, 'new', 1)
    assert not follow.receive(0, 'new', '1')
    follow.reset()
    assert not follow.receive(0, 'new', 1)


def test_expired_cl_intent_does_not_block_a_later_direct_launch():
    follow = observer()
    follow.note_cl_launch(0)
    follow.clock = lambda: 131
    assert follow.receive(0, 'session-token', 1)


def test_app_only_copies_primary_trigger_without_primary_command(monkeypatch):
    from tests.test_live_set_generation import load_app_module
    from unittest.mock import Mock
    app = load_app_module()
    follow = observer()
    monkeypatch.setattr(app, 'backup_scene_follow', follow)
    monkeypatch.setattr(app, 'state', {'set_generation': 7, 'set_ready': True})
    monkeypatch.setattr(app, 'hot_backup_generation', 7)
    monkeypatch.setattr(app.ableton_transport, 'resolved_host', '127.0.0.1')
    backup = Mock()
    primary = Mock()
    monkeypatch.setattr(app.hot_backup, 'offer', backup)
    monkeypatch.setattr(app.ableton_transport, 'send', primary)
    app.osc_reply('/live/scene/get/is_triggered', 0, 'session-token', 1, source_host='192.168.1.138')
    backup.assert_not_called()
    app.osc_reply('/live/scene/get/is_triggered', 0, 'session-token', 1, source_host='127.0.0.1')
    app.osc_reply('/live/scene/get/is_triggered', 0, 'session-token', 1, source_host='127.0.0.1')
    backup.assert_called_once_with('/live/scene/fire', 0)
    primary.assert_not_called()


def test_transport_initial_state_never_stops_backup_but_real_stop_does():
    follow = observer()
    assert not follow.receive_transport_stop('session-token', 0)
    assert not follow.receive_transport_stop('old', 1)
    assert not follow.receive_transport_stop('session-token', 1)
    assert follow.receive_transport_stop('session-token', 0)
    assert not follow.receive_transport_stop('session-token', 0)


def test_initial_cl_trigger_consumes_intent_without_blocking_next_launch():
    follow = BackupSceneFollow(clock=lambda: 100)
    follow.reset('new', (0,))
    follow.note_cl_launch(0)
    assert not follow.receive(0, 'new', 1)
    follow.receive(0, 'new', 0)
    assert follow.receive(0, 'new', 1)


def test_track_listener_refresh_does_not_disable_scene_follow(monkeypatch):
    from tests.test_live_set_generation import load_app_module
    from unittest.mock import Mock
    app = load_app_module()
    follow = observer()
    monkeypatch.setattr(app, 'backup_scene_follow', follow)
    monkeypatch.setattr(app, '_playing_listener_token', 'track-token')
    monkeypatch.setattr(app, '_playing_listener_tracks', {0: None})
    monkeypatch.setattr(app.ableton_transport, 'send', Mock(return_value=True))
    with app.lock:
        app.stop_playing_scene_listeners_locked()
    assert follow.token == 'session-token'
    assert follow.receive(0, 'session-token', 1)
    assert all('/scene/' not in call.args[0] for call in app.ableton_transport.send.call_args_list)


def test_immediate_launch_completion_only_matches_live_log_sequence():
    follow = observer()
    # Actual Live/AbletonOSC trace: initial False, then False per immediate fire.
    assert follow.receive(0, 'session-token', False)
    assert follow.receive(0, 'session-token', False)
    assert follow.forwarded == 2


def test_cl_immediate_completion_is_suppressed_once():
    follow = observer()
    follow.note_cl_launch(0)
    assert not follow.receive(0, 'session-token', False)
    assert follow.suppressed_cl == 1
    assert follow.receive(0, 'session-token', False)


def test_quantized_true_then_false_is_only_one_launch():
    follow = observer()
    assert follow.receive(0, 'session-token', True)
    assert not follow.receive(0, 'session-token', False)
    assert follow.forwarded == 1
