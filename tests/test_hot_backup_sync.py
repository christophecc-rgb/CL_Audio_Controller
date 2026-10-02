"""No Live required: real worker, captured UDP and real PRIMARY handlers."""
import ast
import threading
import time
from pathlib import Path
from unittest.mock import Mock, patch
from security_test_helper import isolated_admin_client

import pytest
from pythonosc.osc_message import OscMessage
from hot_backup_sync import Config, HotBackup, MAX_AGE
from osc_transport import OSCTransport

ROOT = Path(__file__).resolve().parents[1]

class Socket:
    def __init__(self):
        self.sent = []
    def setblocking(self, flag):
        assert flag is False
    def sendto(self, data, target):
        msg = OscMessage(data)
        self.sent.append((msg.address, msg.params, target))
    def close(self):
        pass


def backup():
    b = HotBackup(clock=lambda: 100)
    b.config = Config(1, 'hot_backup', '192.0.2.2', 'Show', 120)
    return b


def ready(b, name='Show', tempo=120, playing=0):
    for key, value in [('name', name), ('tempo', tempo), ('is_playing', playing)]:
        b.receive(b.config.host, '/live/song/get/' + key, (value,))
    return b._health(b.config)


def primary_scope(b):
    # Extract the exact app boundary without starting any application services.
    names = {'send', 'copy_to_backup', 'send_user_transport'}
    nodes = [n for n in ast.parse((ROOT / 'app.py').read_text()).body
             if isinstance(n, ast.FunctionDef) and n.name in names]
    transport = Mock()
    ns = dict(ableton_transport=transport, hot_backup=b,
              hot_backup_generation=7, state={'set_generation': 7})
    exec(compile(ast.Module(body=nodes, type_ignores=[]), 'app boundaries', 'exec'), ns)
    return ns, transport


def test_default_mode_is_passive():
    b = HotBackup()
    b.offer('/live/song/continue_playing')
    assert b.events.empty() and b.thread is None
    assert b.snapshot()['mode'] == 'mtc'


@pytest.mark.parametrize('address,args', [
    ('/live/song/continue_playing', ()), ('/live/song/stop_playing', ()),
    ('/live/song/set/current_song_time', (15600.25,)),
])
def test_primary_first_even_when_backup_offer_raises(address, args):
    b = backup()
    ns, primary = primary_scope(b)
    def fail(*_):
        primary.send.assert_called_once_with(address, *args)
        raise OSError('backup broken')
    b.offer = fail
    assert ns['send_user_transport'](address, *args) is None  # historical send() result
    primary.send.assert_called_once_with(address, *args)


@pytest.mark.parametrize('address,args', [
    ('/live/song/continue_playing', ()), ('/live/song/stop_playing', ()),
    ('/live/song/set/current_song_time', (15600.25,)),
])
def test_slow_backup_worker_never_blocks_primary(address, args):
    entered, release = threading.Event(), threading.Event()
    class SlowSocket(Socket):
        def sendto(self, data, target):
            entered.set()
            release.wait(3)
    b = HotBackup(socket_factory=lambda *_: SlowSocket())
    b.configure('hot_backup', '192.0.2.2', 'Show', 120)
    try:
        assert entered.wait(1)
        ns, primary = primary_scope(b)
        completed = threading.Event()
        worker = threading.Thread(target=lambda: (ns['send_user_transport'](address, *args), completed.set()))
        worker.start()
        assert completed.wait(.2), 'PRIMARY waited for BACKUP'
        primary.send.assert_called_once_with(address, *args)
        assert not release.is_set()
        worker.join(1)
    finally:
        b.shutdown.set()
        release.set()
        b.thread.join(1)


def test_offline_backup_drops_go_but_attempts_stop():
    b, sock = backup(), Socket()
    assert not b._health(b.config)
    b.offer('/live/song/continue_playing')
    b._event(sock, b.config, False, b.events.get_nowait())
    assert sock.sent == []
    b.offer('/live/song/stop_playing')
    b._event(sock, b.config, False, b.events.get_nowait())
    assert sock.sent[0][0] == '/live/song/stop_playing'
    assert b.dropped == 1


def test_both_targets_receive_same_beats_and_go():
    b, sock = backup(), Socket()
    assert ready(b)
    ns, primary = primary_scope(b)
    for address, args in [('/live/song/set/current_song_time', (15600.25,)),
                          ('/live/song/continue_playing', ())]:
        ns['send_user_transport'](address, *args)
        b._event(sock, b.config, True, b.events.get_nowait())
    assert [c.args for c in primary.send.call_args_list] == [
        ('/live/song/set/current_song_time', 15600.25), ('/live/song/continue_playing',)]
    assert [(a, p) for a, p, _ in sock.sent] == [
        ('/live/song/set/current_song_time', [15600.25]), ('/live/song/continue_playing', [])]


def test_socket_failure_cannot_escape_worker_into_primary():
    b = backup()
    assert ready(b)
    sock = Socket()
    sock.sendto = Mock(side_effect=OSError('unreachable'))
    ns, primary = primary_scope(b)
    ns['send_user_transport']('/live/song/continue_playing')
    with pytest.raises(OSError):
        b._event(sock, b.config, True, b.events.get_nowait())
    assert b.missed
    ns['send_user_transport']('/live/song/stop_playing')
    assert primary.send.call_count == 2


@pytest.mark.parametrize('key,value', [('tempo', float('nan')), ('is_playing', 'invalid'), ('name', 7)])
def test_invalid_reply_only_changes_backup(key, value):
    b = backup()
    b.receive(b.config.host, '/live/song/get/' + key, (value,))
    assert not b._health(b.config)
    assert b.info['state'] == 'ERROR'


@pytest.mark.parametrize('name,tempo', [('Wrong', 120), ('Show', 99)])
def test_wrong_set_or_tempo_not_ready(name, tempo):
    b = backup()
    assert not ready(b, name, tempo)
    assert b.info['state'] == 'NOT READY'


def test_timeout_no_old_go_replay_after_reconnect():
    b, sock = backup(), Socket()
    assert ready(b)
    b.offer('/live/song/continue_playing')
    b.clock = lambda: 104
    assert not b._health(b.config)
    b._event(sock, b.config, False, b.events.get_nowait())
    assert not sock.sent
    assert not ready(b)  # lost event requires explicit rearm, no recovery GO
    assert b.info['state'] == 'NOT READY'


def test_reply_sources_never_mix_even_with_same_osc_address():
    b = backup()
    with patch('osc_transport.udp_client.SimpleUDPClient'):
        p = OSCTransport(host='127.0.0.1')
    p.foreign_reply_handler = b.receive
    p._active_request = {'address': '/live/song/get/tempo', 'args': (), 'sent_at': time.time()}
    p._receive('/live/song/get/tempo', 99, source_host=b.config.host)
    assert 'response' not in p._active_request and not p.connected
    p._receive('/live/song/get/tempo', 120, source_host='127.0.0.1')
    assert p._active_request['response'] == (120,)
    assert b.replies.get_nowait()[3] == (99,)
    p.foreign_reply_handler = Mock(side_effect=ValueError('invalid backup'))
    p._receive('/live/song/get/tempo', 30, source_host=b.config.host)
    assert p._active_request['response'] == (120,)


def test_no_corrections_during_four_minutes_and_direct_live_events():
    b, sock = backup(), Socket()
    assert ready(b)
    for second in range(240):
        b.clock = lambda: 100 + second
        ready(b, tempo=120 + second, playing=1)  # automation is not corrected
        b.receive(b.config.host, '/live/song/get/current_song_time', (second * 2 + .05,))
    assert not sock.sent and b.events.empty()


def test_mtc_switch_discards_pending_backup_commands():
    b, sock = backup(), Socket()
    b.offer('/live/song/continue_playing')
    item = b.events.get_nowait()
    b.configure('mtc')
    b._event(sock, b.config, True, item)
    assert not sock.sent
    assert b.snapshot()['mode'] == 'mtc'


def test_bounded_queue_and_expiry():
    b = backup()
    ns, primary = primary_scope(b)
    for _ in range(100):
        ns['send_user_transport']('/live/song/stop_playing')
    assert primary.send.call_count == 100
    assert b.events.qsize() == 64 and b.dropped == 36


def test_set_change_never_copies_to_backup():
    b = backup()
    ns, primary = primary_scope(b)
    ns['state']['set_generation'] = 8
    ns['send_user_transport']('/live/song/continue_playing')
    primary.send.assert_called_once()
    assert b.events.empty()


def test_no_views_tempo_or_selected_scene_forwarded():
    b = backup()
    for address in ['/live/view/set/selected_scene', '/live/song/set/tempo',
                    '/live/application/view/show_view']:
        b.offer(address, 1)
    assert b.events.empty()
    source = (ROOT / 'app.py').read_text()
    assert 'SCAN_PLAYING_SCENE_FROM_TRACKS = False' in source
    calls = [n for n in ast.walk(ast.parse(source)) if isinstance(n, ast.Call)
             and isinstance(n.func, ast.Name) and n.func.id == 'show_session_view']
    assert not calls


def test_actual_arrangement_go_is_unchanged_when_backup_faults(monkeypatch):
    import app
    commands = []
    live = {'playing': False, 'time': 64}
    def send(address, *args):
        commands.append((address, args))
        if address.endswith('/continue_playing'):
            live['playing'] = True
        if address.endswith('/set/current_song_time'):
            live['time'] = args[0]
        return True
    monkeypatch.setattr(app.ableton_transport, 'send', send)
    monkeypatch.setattr(app, 'generation_is_current', lambda _: True)
    monkeypatch.setattr(app, 'query', lambda address, **kw: (live['playing'] if address.endswith('is_playing') else live['time'],))
    monkeypatch.setattr(app, 'send_midi_monitor_scene_context', lambda *args: None)
    monkeypatch.setattr(app, 'hot_backup_generation', app.state['set_generation'])
    monkeypatch.setattr(app.hot_backup, 'offer', Mock(side_effect=OSError('backup failed')))
    assert app.execute_arrangement_marker_go(15600, 'Cue', 1, 7) == (True, 'GO confirmé par Ableton')
    assert commands == [('/live/song/set/back_to_arranger', (0,)),
                        ('/live/song/continue_playing', ()),
                        ('/live/song/set/current_song_time', (15600,))]


def test_explicit_settings_route_no_transport_commands(monkeypatch):
    import app
    b = HotBackup()
    monkeypatch.setattr(b, 'thread', object())  # do not start real worker/network
    monkeypatch.setattr(app, 'hot_backup', b)
    monkeypatch.setattr(app, 'state', {**app.state, 'set_ready': True, 'is_playing': False,
                                      'set_generation': 7, 'current_set_name': 'Show'})
    monkeypatch.setattr(app, 'generation_is_current', lambda _: True)
    no_query = Mock(side_effect=AssertionError('No PRIMARY query during BACKUP setup'))
    monkeypatch.setattr(app, 'query', no_query)
    monkeypatch.setattr(app.ableton_transport, 'last_song_tempo', (120, time.monotonic()))
    monkeypatch.setattr(app.socket, 'gethostbyname_ex', lambda _: ('local', [], ['127.0.0.1']))
    send = Mock()
    monkeypatch.setattr(app.ableton_transport, 'send', send)
    with isolated_admin_client(app) as client:
        assert client.get('/api/hot-backup').json['mode'] == 'mtc'
        data = dict(mode='hot_backup', host='192.0.2.2', ext_off=True, same_set=True)
        assert client.post('/api/hot-backup', json={**data, 'ext_off': False}).status_code == 400
        assert client.post('/api/hot-backup', json={**data, 'host': '127.0.0.1'}).status_code == 400
        response = client.post('/api/hot-backup', json=data)
        assert response.status_code == 200
        assert b.config.mode == 'hot_backup' and b.config.expected_tempo == 120
        assert b.events.empty()
        send.assert_not_called()
        assert client.post('/api/hot-backup', json={'mode': 'mtc'}).json['mode'] == 'mtc'


def test_settings_reject_enable_while_playing(monkeypatch):
    import app
    monkeypatch.setattr(app, 'state', {**app.state, 'set_ready': True, 'is_playing': True})
    with isolated_admin_client(app) as client:
        r = client.post(    '/api/hot-backup', json=dict(
            mode='hot_backup', host='192.0.2.2', ext_off=True, same_set=True))
        assert r.status_code == 400


def test_live_error_and_malformed_arity_never_touch_primary():
    b = backup()
    ready(b)
    b.receive(b.config.host, '/live/song/get/tempo', (120, 90))
    assert not b._health(b.config)
    b.receive(b.config.host, '/live/error', ('unknown method',))
    assert not ready(b)
    assert b.missed


def test_foreign_status_cannot_change_primary_unsolicited_state():
    with patch('osc_transport.udp_client.SimpleUDPClient'):
        p = OSCTransport(host='127.0.0.1', unsolicited_handler=Mock())
    p._receive('/live/song/get/is_playing', 0, source_host='192.0.2.2')
    p._unsolicited_handler.assert_not_called()
    assert not p.connected


def test_actual_stop_action_succeeds_with_backup_socket_exception(monkeypatch):
    import app
    monkeypatch.setattr(app, 'state', {**app.state, 'set_ready': True, 'set_generation': 7})
    monkeypatch.setattr(app, 'hot_backup_generation', 7)
    monkeypatch.setattr(app.hot_backup, 'offer', Mock(side_effect=OSError('offline')))
    primary = Mock()
    monkeypatch.setattr(app.ableton_transport, 'send', primary)
    monkeypatch.setattr(app, 'write_keyboard_diagnostic', lambda *args: None)
    response = app.app.test_client().post('/action', json={'action': 'stop'})
    assert response.status_code == 200 and response.json['ok']
    primary.assert_called_once_with('/live/song/stop_playing')


def test_actual_go_copies_each_send_without_waiting_for_primary_confirmation(monkeypatch):
    import app
    commands, copies = [], []
    live = {'playing': False, 'time': 64}
    monkeypatch.setattr(app, 'hot_backup_generation', app.state['set_generation'])
    monkeypatch.setattr(app.hot_backup, 'offer', lambda address, *args: copies.append((address, args)))
    def send(address, *args):
        commands.append((address, args))
        if address.endswith('/continue_playing'):
            live['playing'] = True
        if address.endswith('/set/current_song_time'):
            live['time'] = args[0]
        return True
    def query(address, **kw):
        if commands:
            assert copies == commands  # copy precedes the next PRIMARY readback
        return (live['playing'] if address.endswith('is_playing') else live['time'],)
    monkeypatch.setattr(app.ableton_transport, 'send', send)
    monkeypatch.setattr(app, 'query', query)
    monkeypatch.setattr(app, 'generation_is_current', lambda _: True)
    monkeypatch.setattr(app, 'send_midi_monitor_scene_context', lambda *args: None)
    assert app.execute_arrangement_marker_go(15600, 'Cue', 1, 7)[0]
    assert commands == copies


def test_real_worker_four_minutes_sends_only_read_only_probes():
    now = [0.0]
    b = HotBackup(clock=lambda: now[0])
    b.config = Config(1, 'hot_backup', '192.0.2.2', 'Show', 120)
    class ClockSocket(Socket):
        def sendto(self, data, target):
            super().sendto(data, target)
            address = self.sent[-1][0]
            key = address.rsplit('/', 1)[-1]
            b.receive(b.config.host, address, ({'name': 'Show', 'tempo': 120, 'is_playing': 1}[key],))
            if key == 'tempo':
                now[0] += 1
                if now[0] >= 240:
                    b.shutdown.set()
    sock = ClockSocket()
    b.socket_factory = lambda *_: sock
    b.events.get = Mock(side_effect=__import__('queue').Empty)
    b._run()
    assert len(sock.sent) == 720
    assert all(address.startswith('/live/song/get/') for address, _, _ in sock.sent)


def test_actual_next_prepares_backup_in_beats_without_changing_primary(monkeypatch):
    import app
    monkeypatch.setattr(app, 'state', {**app.state, 'set_ready': True, 'set_generation': 7,
        'arrangement_time': 64, 'arrangement_markers': [
            {'name': 'A', 'time': 64}, {'name': 'B', 'time': 128}]})
    monkeypatch.setattr(app, 'hot_backup_generation', 7)
    backup_calls = Mock()
    monkeypatch.setattr(app.hot_backup, 'offer', backup_calls)
    primary = Mock()
    monkeypatch.setattr(app.ableton_transport, 'send', primary)
    monkeypatch.setattr(app, 'show_arrangement_view', lambda: None)
    monkeypatch.setattr(app, 'write_keyboard_diagnostic', lambda *args: None)
    response = app.app.test_client().post('/action', json={'action': 'arrangement_next'})
    assert response.status_code == 200
    assert [c.args for c in primary.call_args_list] == [
        ('/live/song/stop_playing',), ('/live/song/set/current_song_time', 128.0)]
    assert backup_calls.call_args_list == primary.call_args_list


def test_live_feedback_never_enqueues_a_backup_event(monkeypatch):
    import app
    calls = Mock()
    monkeypatch.setattr(app.hot_backup, 'offer', calls)
    # The existing feedback handler only updates state, not the new copy boundary.
    monkeypatch.setattr(app, 'state', {**app.state, 'set_generation': 7})
    with app.lock:
        app.apply_osc_response_locked('/live/song/get/is_playing', (1,), 7)
        app.apply_osc_response_locked('/live/song/get/is_playing', (0,), 7)
    calls.assert_not_called()
