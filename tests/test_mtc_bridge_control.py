"""Exercise existing Show Control functions without importing/autostarting the app."""
import ast
from pathlib import Path
import unittest
import threading
import subprocess
from unittest.mock import Mock, mock_open, patch

ROOT = Path(__file__).resolve().parents[1]

class BridgeControlTests(unittest.TestCase):
    def setUp(self):
        tree = ast.parse((ROOT / 'launcher_control.py').read_text())
        functions = [n for n in tree.body if isinstance(n, ast.FunctionDef)
                     and (n.name.startswith('_cl_mtc_bridge_') or n.name in
                          {'cl_mtc_bridge_restart', 'cl_mtc_bridge_status', 'stop_owned_child'})]
        for node in functions:
            node.decorator_list = []
        self.scope = {'__file__': str(ROOT / 'launcher_control.py'),
                      'owned_children_lock': threading.RLock(), 'MTC_BRIDGE_PROCESS': None,
                      'launcher_stopping': threading.Event(), 'subprocess': subprocess}
        exec(compile(ast.Module(body=functions, type_ignores=[]), '<bridge control>', 'exec'), self.scope)
        self.scope['_cl_mtc_bridge_executable'] = Mock(return_value=Path('/tmp/bridge'))

    def test_existing_process_prevents_double_launch(self):
        with patch('subprocess.run', return_value=Mock(stdout='123\n')), \
             patch('pathlib.Path.exists', return_value=True), patch('subprocess.Popen') as launch:
            for _ in range(2):
                self.assertTrue(self.scope['_cl_mtc_bridge_start_process']()['running'])
            launch.assert_not_called()

    def test_restart_stops_owned_handle_then_launches_once(self):
        owned = Mock(pid=123)
        owned.poll.return_value = None
        self.scope['MTC_BRIDGE_PROCESS'] = owned
        self.scope['_cl_mtc_bridge_pids'] = Mock(return_value=[])
        with patch('time.sleep'), patch('pathlib.Path.exists', return_value=True), \
             patch('builtins.open', mock_open()), \
             patch('subprocess.Popen', return_value=Mock(pid=456)) as launch:
            result = self.scope['cl_mtc_bridge_restart']()
            owned.terminate.assert_called_once()
            owned.wait.assert_called_once()
            launch.assert_called_once()
            self.assertEqual(result['pid'], 456)

    def test_external_bridge_is_not_adopted_or_stopped(self):
        self.scope['_cl_mtc_bridge_pids'] = Mock(return_value=[123])
        with patch('os.kill') as kill, patch('pathlib.Path.exists', return_value=True), \
             patch('subprocess.Popen') as launch:
            self.assertFalse(self.scope['_cl_mtc_bridge_start_process']()['owned'])
            self.assertFalse(self.scope['_cl_mtc_bridge_stop_process']()['owned'])
            kill.assert_not_called()
            launch.assert_not_called()

    def test_restart_does_not_duplicate_process_if_stop_fails(self):
        self.scope['_cl_mtc_bridge_stop_process'] = Mock(return_value={'ok': False})
        self.scope['_cl_mtc_bridge_pids'] = Mock(return_value=[123])
        with patch('time.sleep'), patch('pathlib.Path.exists', return_value=True), \
             patch('subprocess.Popen') as launch:
            self.assertEqual(self.scope['cl_mtc_bridge_restart']()['pids'], [123])
            launch.assert_not_called()

if __name__ == '__main__':
    unittest.main()
