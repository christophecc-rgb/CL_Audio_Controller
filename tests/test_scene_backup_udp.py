import json
import threading
import time
from scene_backup_udp import SceneBackupUDP


class Socket:
    def __init__(self, fail=False, gate=None):
        self.packets = []
        self.closed = False
        self.fail, self.gate = fail, gate
        self.entered = threading.Event()
    def setblocking(self, value):
        assert value is False
    def sendto(self, data, target):
        self.entered.set()
        if self.gate:
            assert self.gate.wait(2)
        if self.fail:
            raise OSError('offline')
        self.packets.append((data, target))
    def close(self):
        self.closed = True


def backup(sock, **kwargs):
    obj = SceneBackupUDP(socket_factory=lambda *args: sock, **kwargs)
    obj.configure(enabled=True, destinations=['127.0.0.1', '127.0.0.2'])
    return obj


def wait_for(predicate):
    deadline = time.monotonic() + 2
    while not predicate():
        assert time.monotonic() < deadline
        time.sleep(.002)


def test_fast_handoff_three_identical_v1_packets_multi_destination():
    gate = threading.Event()
    sock = Socket(gate=gate)
    obj = backup(sock)
    try:
        started = time.monotonic()
        obj.scene_launched(42)
        assert time.monotonic() - started < .03
        assert sock.entered.wait(1)
        gate.set()
        wait_for(lambda: obj.snapshot()['sent_packets'] == 6)
        packets = [json.loads(data) for data, target in sock.packets]
        assert packets == [dict(v=1, show='OP2026', session=obj.session, seq=1, scene=42)] * 6
        assert [target for data, target in sock.packets].count(('127.0.0.1', 12042)) == 3
        assert obj.snapshot()['last_scene_sent'] == 42
    finally:
        gate.set()
        assert obj.close()
        assert sock.closed


def test_bounded_queue_and_expiration_never_replay_old_scenes():
    gate = threading.Event()
    sock = Socket(gate=gate)
    obj = backup(sock, queue_size=1, max_event_age=.025)
    try:
        obj.scene_launched(1)
        assert sock.entered.wait(1)
        obj.scene_launched(2)
        obj.scene_launched(3)
        assert obj.snapshot()['queued'] == 1
        assert obj.snapshot()['dropped'] == 1
        time.sleep(.04)
        gate.set()
        wait_for(lambda: obj.snapshot()['expired'] >= 2)
        assert all(json.loads(data)['scene'] == 1 for data, target in sock.packets)
    finally:
        gate.set()
        assert obj.close()


def test_network_errors_never_escape_and_worker_closes():
    sock = Socket(fail=True)
    obj = backup(sock)
    try:
        obj.scene_launched(1)
        wait_for(lambda: obj.snapshot()['send_errors'] == 6)
        assert obj.snapshot()['sent_packets'] == 0
    finally:
        assert obj.close()
    assert sock.closed
    assert obj.close()
    obj.scene_launched(2)
    assert obj.snapshot()['enqueued'] == 1


def test_close_interrupts_delays_and_discards_pending_work():
    sock = Socket()
    obj = backup(sock, copy_interval=10)
    obj.scene_launched(1)
    assert sock.entered.wait(1)
    obj.scene_launched(2)
    started = time.monotonic()
    assert obj.close()
    assert time.monotonic() - started < .2
    assert obj.snapshot()['queued'] == 0
    assert obj.snapshot()['dropped'] >= 1
    assert sock.closed


def test_session_change_discards_pending_old_epoch():
    gate = threading.Event()
    sock = Socket(gate=gate)
    obj = backup(sock)
    try:
        obj.scene_launched(1)
        assert sock.entered.wait(1)
        obj.scene_launched(2)
        obj.new_session()
        gate.set()
        wait_for(lambda: obj.snapshot()['dropped'] >= 2)
        assert obj.seq == 0
        assert all(json.loads(data)['scene'] != 2 for data, target in sock.packets)
    finally:
        gate.set()
        assert obj.close()


def test_actual_go_handoff_does_not_wait_for_backup_network():
    import ast
    from contextlib import nullcontext
    from pathlib import Path
    from unittest.mock import Mock
    gate = threading.Event()
    sock = Socket(gate=gate)
    obj = backup(sock)
    source = Path(__file__).resolve().parents[1] / 'app.py'
    node = next(n for n in ast.parse(source.read_text()).body
                if isinstance(n, ast.FunctionDef) and n.name == 'execute_go_transaction')
    scope = dict(time=time, threading=threading, scene_transaction_lock=threading.RLock(),
                 lock=threading.RLock(), completed_go_requests={},
                 state={'set_generation': 1, 'set_ready': True, 'scenes': {0: 'Test'}},
                 clamp_scene_number=lambda n: n - 1, generation_is_current=lambda n: True,
                 ableton_transport=Mock(serialized_queries=Mock(side_effect=lambda *, priority=False: nullcontext())),
                 write_keyboard_diagnostic=Mock(),
                 _query_with_query_lock_held=lambda *a, **kw: [0], send=Mock(),
                 send_midi_monitor_scene_context=Mock(), record_go_midi_expectations=Mock(),
                 scene_backup_udp=obj, copy_to_backup=Mock(), parse_scene_duration_seconds=lambda n: 10,
                 schedule_selected_scene_duration_refresh=Mock())
    exec(compile(ast.fix_missing_locations(ast.Module(body=[ast.ImportFrom(module='__future__', names=[ast.alias(name='annotations')], level=0), node],
                            type_ignores=[])), '<GO integration>', 'exec'), scope)
    try:
        started = time.monotonic()
        scope['backup_scene_follow'] = Mock()
        assert scope['execute_go_transaction']('test-go', 1, 1)[0]
        assert time.monotonic() - started < .05
        scope['ableton_transport'].serialized_queries.assert_called_once_with(priority=True)
        scope['write_keyboard_diagnostic'].assert_called_once()
        assert scope['write_keyboard_diagnostic'].call_args.args[0]['event'] == 'go-scene-command-sent'
        assert sock.entered.wait(1)
        assert not gate.is_set()
        scope['send'].assert_any_call('/live/scene/fire_as_selected', 0)
    finally:
        gate.set()
        assert obj.close()
