"""Isolated publisher tests: never import the backend or register real Bonjour."""
import ast
import atexit
from pathlib import Path
import signal
import subprocess
import sys
import threading
from unittest.mock import Mock

SOURCE = Path(__file__).resolve().parents[1] / 'app.py'
NAMES = {'_exit_on_midi_expected_sigterm', 'install_midi_expected_sigterm_cleanup',
         'start_midi_expected_bonjour_publisher', 'stop_midi_expected_bonjour_publisher'}


def publisher_source():
    tree = ast.parse(SOURCE.read_text())
    return '\n\n'.join(ast.unparse(n) for n in tree.body
                       if isinstance(n, ast.FunctionDef) and n.name in NAMES)


def namespace():
    ns = dict(threading=threading, signal=Mock(SIGTERM=signal.SIGTERM, SIG_DFL=signal.SIG_DFL),
              subprocess=Mock(DEVNULL=subprocess.DEVNULL),
              _midi_expected_bonjour_lock=threading.Lock(),
              _midi_expected_bonjour_process=None,
              MIDI_EXPECTED_BONJOUR_NAME='CL Show Control Expected',
              MIDI_EXPECTED_BONJOUR_TYPE='_cl-midi-expected._udp',
              MIDI_EXPECTED_UDP_PORT=50023)
    ns['signal'].getsignal.return_value = signal.SIG_DFL
    exec(publisher_source(), ns)
    return ns


def test_start_idempotent_and_command_unchanged():
    ns = namespace()
    proc = ns['subprocess'].Popen.return_value
    proc.poll.return_value = None
    ns['start_midi_expected_bonjour_publisher']()
    ns['start_midi_expected_bonjour_publisher']()
    assert ns['subprocess'].Popen.call_count == 1
    assert ns['subprocess'].Popen.call_args.args[0] == [
        'dns-sd', '-R', 'CL Show Control Expected', '_cl-midi-expected._udp', 'local.', '50023']


def test_stop_reaps_only_owned_child_and_is_idempotent():
    ns = namespace()
    proc = Mock()
    proc.poll.return_value = None
    ns['_midi_expected_bonjour_process'] = proc
    ns['stop_midi_expected_bonjour_publisher']()
    ns['stop_midi_expected_bonjour_publisher']()
    proc.terminate.assert_called_once()
    proc.wait.assert_called_once_with(timeout=1.0)
    proc.kill.assert_not_called()


def test_timeout_kills_and_reaps_owned_child():
    ns = namespace()
    proc = Mock()
    proc.poll.return_value = None
    proc.wait.side_effect = [subprocess.TimeoutExpired('fake', 1), 0]
    ns['_midi_expected_bonjour_process'] = proc
    ns['stop_midi_expected_bonjour_publisher']()
    proc.kill.assert_called_once()
    assert proc.wait.call_count == 2


def test_existing_host_handler_preserved():
    ns = namespace()
    ns['signal'].getsignal.return_value = lambda *_: None
    ns['install_midi_expected_sigterm_cleanup']()
    ns['signal'].signal.assert_not_called()


def test_worker_does_not_install_signal_handler():
    ns = namespace()
    worker = threading.Thread(target=ns['install_midi_expected_sigterm_cleanup'])
    worker.start()
    worker.join()
    ns['signal'].signal.assert_not_called()


def test_spawn_error_leaves_no_process():
    ns = namespace()
    ns['subprocess'].Popen.side_effect = OSError('test only')
    ns['start_midi_expected_bonjour_publisher']()
    assert ns['_midi_expected_bonjour_process'] is None


def test_sigterm_and_normal_exit_reap_dummy_child(tmp_path):
    # Only these newly created Python workers receive a signal, never production.
    for mode in ('normal', 'sigterm'):
        result = tmp_path / (mode + '.txt')
        code = '''import atexit, signal, subprocess, threading, sys, os
_midi_expected_bonjour_lock = threading.Lock()
''' + publisher_source() + '''
_midi_expected_bonjour_process = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])
child = _midi_expected_bonjour_process
from pathlib import Path
def record():
    Path(sys.argv[1]).write_text(str(child.poll()))
atexit.register(record)
atexit.register(stop_midi_expected_bonjour_publisher)
install_midi_expected_sigterm_cleanup()
if sys.argv[2] == 'sigterm':
    os.kill(os.getpid(), signal.SIGTERM)
'''
        done = subprocess.run([sys.executable, '-c', code, str(result), mode], timeout=5)
        assert done.returncode == (143 if mode == 'sigterm' else 0)
        assert result.read_text() == str(-signal.SIGTERM)
