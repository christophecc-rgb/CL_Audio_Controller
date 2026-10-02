"""Publisher lifecycle under a fake Live Manager; no processes or LAN needed."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import types
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]


class PublisherProcessTests(unittest.TestCase):
    def setUp(self):
        class Manager:
            def __init__(self, server):
                self.osc_server = server
                self.scheduled = []
                self.disconnected = False
            def schedule_message(self, delay, callback):
                self.scheduled.append((delay, callback))
            def disconnect(self):
                self.disconnected = True
        package = types.ModuleType('publisher_fixture')
        package.__path__ = []
        manager = types.ModuleType('publisher_fixture.manager')
        manager.Manager = Manager
        self.modules = patch.dict(sys.modules, {'publisher_fixture': package, 'publisher_fixture.manager': manager})
        self.modules.start()
        self.addCleanup(self.modules.stop)
        self.module = self.load_module()
        self.proc = Mock()
        self.proc.poll.return_value = None
        self.proc.wait.return_value = 0
        self.popen = patch.object(self.module.subprocess, 'Popen', return_value=self.proc).start()
        self.addCleanup(patch.stopall)
        self.register = patch.object(self.module.atexit, 'register').start()
        self.unregister = patch.object(self.module.atexit, 'unregister').start()
        patch.object(self.module.socket, 'gethostname', return_value='iMac-de-Sono-2.local').start()
        self.server = Mock()
        self.server._socket.fileno.return_value = 10
        self.server._socket.getsockname.return_value = ('0.0.0.0', 11000)

    def load_module(self):
        spec = importlib.util.spec_from_file_location('publisher_fixture.cl_bonjour', ROOT / 'INSTALLER_AbletonOSC/cl_bonjour.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_arguments_port_txt_and_single_start(self):
        self.server._socket.getsockname.return_value = ('0.0.0.0', 12000)
        manager = self.module.BonjourManager(self.server)
        manager._cl_bonjour_tick()
        manager._cl_bonjour_tick()
        self.popen.assert_called_once_with(
            ['/usr/bin/dns-sd', '-R', 'iMac-de-Sono-2 AbletonOSC', '_cl-ableton._udp',
             'local.', '12000', 'role=ableton', 'protocol=abletonosc', 'version=1'],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, shell=False, close_fds=True)
        self.register.assert_called_once()
        self.server.send.assert_not_called()

    def test_disconnect_terminates_and_reaps_once(self):
        manager = self.module.BonjourManager(self.server)
        manager.disconnect()
        manager.disconnect()
        manager._cl_bonjour_tick()
        self.proc.terminate.assert_called_once()
        self.proc.wait.assert_called_once_with(timeout=0.5)
        self.proc.kill.assert_not_called()
        self.unregister.assert_called_once()
        self.assertTrue(manager.disconnected)
        self.assertEqual(self.popen.call_count, 1)

    def test_kill_fallback_and_reap(self):
        announcement = self.module.Announcement(11000)
        self.proc.wait.side_effect = [subprocess.TimeoutExpired('dns-sd', 0.5), 0]
        announcement.close()
        self.proc.kill.assert_called_once()
        self.assertEqual(self.proc.wait.call_count, 2)
        self.assertIsNone(announcement.process)

    def test_unexpected_exit_reaped_and_retry(self):
        manager = self.module.BonjourManager(self.server)
        self.proc.poll.return_value = 1
        manager._cl_bonjour_tick()
        self.proc.wait.assert_called_once()
        self.proc.terminate.assert_not_called()
        self.assertIsNone(manager._cl_announcement)
        self.proc.poll.return_value = None
        manager._cl_bonjour_tick()
        self.assertEqual(self.popen.call_count, 2)

    def test_spawn_error_is_nonfatal_and_retried(self):
        self.popen.side_effect = OSError('cannot execute dns-sd')
        manager = self.module.BonjourManager(self.server)
        self.assertEqual(len(manager.scheduled), 1)
        manager._cl_bonjour_tick()
        self.assertEqual(self.popen.call_count, 2)
        manager.disconnect()
        self.assertTrue(manager.disconnected)

    def test_reload_reaps_old_owner_before_new_child(self):
        first = self.module.BonjourManager(self.server)
        sequence = []
        self.proc.wait.side_effect = lambda **kw: sequence.append('reaped') or 0
        self.popen.side_effect = lambda *a, **kw: sequence.append('started') or self.proc
        reloaded = self.load_module()
        second = reloaded.BonjourManager(self.server)
        self.assertEqual(sequence, ['reaped', 'started'])
        first._cl_bonjour_tick()
        self.assertEqual(self.popen.call_count, 2)
        second.disconnect()

    def test_cleanup_failure_keeps_ownership_and_blocks_duplicate(self):
        first = self.module.BonjourManager(self.server)
        self.proc.wait.side_effect = subprocess.TimeoutExpired('dns-sd', 0.5)
        second = self.module.BonjourManager(self.server)
        self.assertEqual(self.popen.call_count, 1)
        first.disconnect()
        self.assertTrue(first.disconnected)
        self.assertIsNotNone(first._cl_announcement)
        self.proc.wait.side_effect = None
        second._cl_bonjour_tick()
        self.assertEqual(self.popen.call_count, 2)

    def test_socket_closure_and_port_change(self):
        manager = self.module.BonjourManager(self.server)
        self.server._socket.getsockname.return_value = ('0.0.0.0', 12000)
        manager._cl_bonjour_tick()
        self.assertEqual(self.popen.call_count, 2)
        self.proc.wait.assert_called_once()
        self.server._socket.fileno.return_value = -1
        manager._cl_bonjour_tick()
        self.assertIsNone(manager._cl_announcement)
        self.assertEqual(self.proc.wait.call_count, 2)


if __name__ == '__main__':
    unittest.main()
