"""Isolated launcher shutdown tests: no app imports, processes or production I/O."""
import ast
from pathlib import Path
import subprocess
import threading
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[1]


def scope():
    names = {'cleanup_launcher', 'exit_launcher', 'stop_owned_child', 'stop_midi_console_monitor',
             '_cl_mtc_bridge_stop_process', 'quit_launcher', 'launcher_termination_signal'}
    tree = ast.parse((ROOT / 'launcher_control.py').read_text())
    functions = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in names]
    for n in functions:
        n.decorator_list = []
    ns = dict(threading=threading, subprocess=subprocess, os=Mock(), jsonify=lambda **kw: kw,
              launcher_cleanup_lock=threading.RLock(), server_lifecycle_lock=threading.RLock(),
              owned_children_lock=threading.RLock(), launcher_stopping=threading.Event(),
              launcher_cleanup_result=None, MTC_BRIDGE_PROCESS=None,
              MIDI_CONSOLE_MONITOR_PROCESS=None, launcher_diagnostic_log=Mock(), event=Mock(),
              stop_owned_server=Mock(return_value=(True, 'stopped')), stop_console_simulators=Mock(),
              _cl_mtc_bridge_pids=Mock(return_value=[123]))
    exec(compile(ast.Module(body=functions, type_ignores=[]), '<cleanup>', 'exec'), ns)
    return ns


def test_cleanup_idempotent_reaps_owned_children_only():
    ns = scope()
    monitor, bridge = Mock(), Mock()
    monitor.poll.return_value = bridge.poll.return_value = None
    ns['MIDI_CONSOLE_MONITOR_PROCESS'], ns['MTC_BRIDGE_PROCESS'] = monitor, bridge
    first = ns['cleanup_launcher']()
    assert ns['cleanup_launcher']() is first
    ns['stop_owned_server'].assert_called_once()
    ns['stop_console_simulators'].assert_called_once()
    for child in (monitor, bridge):
        child.terminate.assert_called_once()
        child.wait.assert_called_once()
    assert ns['launcher_stopping'].is_set()


def test_external_mtc_never_signalled():
    ns = scope()
    assert ns['_cl_mtc_bridge_stop_process']()['owned'] is False
    ns['os'].kill.assert_not_called()


def test_cleanup_continues_if_backend_stop_raises():
    ns = scope()
    ns['stop_owned_server'].side_effect = RuntimeError('identity unavailable')
    ns['cleanup_launcher']()
    ns['stop_console_simulators'].assert_called_once()


def test_owned_child_escalates_and_waits():
    ns = scope()
    child = Mock()
    child.poll.return_value = None
    child.wait.side_effect = [subprocess.TimeoutExpired('child', 4), 0]
    ns['stop_owned_child'](child)
    child.terminate.assert_called_once()
    child.kill.assert_called_once()
    assert child.wait.call_count == 2


def test_quit_schedules_same_exit_as_window_and_normal_termination():
    ns = scope()
    fake_threading = Mock()
    ns['threading'] = fake_threading
    ns['quit_launcher']()
    assert fake_threading.Timer.call_args.args == (0.5, ns['exit_launcher'])
    source = (ROOT / 'launcher_control.py').read_text()
    tree = ast.parse(source)
    window = next(n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name == 'quit_when_main_panel_closes')
    assert 'exit_launcher()' in ast.unparse(window)
    assert 'atexit.register(cleanup_launcher)' in source
    assert 'signal.signal(signal.SIGTERM, launcher_termination_signal)' in source
    assert 'finally:\n        cleanup_launcher()' in source
    ns['exit_launcher']()
    ns['stop_console_simulators'].assert_called_once()
    ns['os']._exit.assert_called_once_with(0)
