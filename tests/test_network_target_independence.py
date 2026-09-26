"""Network regression tests; temporary configuration and mocked OSC only."""
import ast
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import ableton_targets as targets
import launcher_control as launcher
import osc_transport

ROOT = Path(__file__).resolve().parents[1]


class NetworkIndependenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'config' / 'network-config.json'
        self.path.parent.mkdir(mode=0o700)
        self.payload = {
            'schema_version': 2, 'active_mode': 'local',
            'cl_server': {'mode': 'paradis', 'host': '192.168.1.53'},
            'profiles': {
                'local': {'mode': 'local', 'host': '127.0.0.1', 'send_port': 11000, 'reply_port': 11001},
                'remote': {'mode': 'remote', 'host': '192.168.1.53', 'send_port': 11000, 'reply_port': 11001, 'name': None},
            },
        }
        self.path.write_text(json.dumps(self.payload))
        self.path.chmod(0o600)

    def test_v2_read_is_lossless_and_server_changes_preserve_both_profiles(self):
        original = self.path.read_bytes()
        self.assertEqual(targets.load_profiles(self.path).remote.host, '192.168.1.53')
        self.assertEqual(self.path.read_bytes(), original)
        with mock.patch.object(launcher, 'load_profiles', side_effect=lambda: targets.load_profiles(self.path)), mock.patch.object(launcher, 'save_profiles', side_effect=lambda p: targets.save_profiles(p, self.path)), mock.patch.object(launcher, 'selected_cl_status', return_value=({}, {}, {})):
            for mode, host in [('local', ''), ('manual', '192.168.3.64'), ('paradis', ''), ('local', '')]:
                result = launcher.app.test_client().post('/network-config', json={'cl_server': {'mode': mode, 'host': host}})
                self.assertEqual(result.status_code, 200)
                saved = json.loads(self.path.read_text())
                self.assertEqual(saved['profiles'], self.payload['profiles'])
                self.assertEqual(saved['active_mode'], 'local')
                self.assertEqual(saved['schema_version'], 2)

    def test_local_remote_local_remote_persists_target_with_local_backend(self):
        with mock.patch.object(launcher, 'load_profiles', side_effect=lambda: targets.load_profiles(self.path)), mock.patch.object(launcher, 'save_profiles', side_effect=lambda p: targets.save_profiles(p, self.path)), mock.patch.object(launcher, 'is_paradis_server_machine', return_value=True), mock.patch.object(launcher, 'tcp_ok', return_value=False), mock.patch.object(launcher, 'get_lan_ip', return_value='192.168.1.54'), mock.patch.object(launcher, 'event'):
            for mode in ['local', 'remote', 'local', 'remote']:
                payload = dict(self.payload['profiles'][mode])
                result = launcher.app.test_client().post('/network-config', json=payload)
                self.assertEqual(result.status_code, 200, result.get_json())
                profiles = targets.load_profiles(self.path)
                self.assertFalse(launcher.cl_server_is_remote(profiles))
                self.assertEqual(profiles.remote.host, '192.168.1.53')
                self.assertEqual(profiles.active_mode, mode)
                self.assertEqual(profiles.cl_server_mode, 'paradis')
                expected = '192.168.1.53' if mode == 'remote' else '127.0.0.1'
                self.assertEqual(targets.load_target(self.path).host, expected)

    def test_backend_startup_honors_explicit_target_despite_other_bonjour_service(self):
        # Execute the actual startup block without loading unrelated MIDI or workers.
        tree = ast.parse((ROOT / 'app.py').read_text())
        def assigns(node, name):
            return isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == name for t in node.targets)
        start = next(i for i, n in enumerate(tree.body) if assigns(n, 'ableton_target'))
        end = next(i for i, n in enumerate(tree.body) if assigns(n, 'ableton_transport'))
        startup = compile(ast.Module(body=tree.body[start:end + 1], type_ignores=[]), 'app.py', 'exec')
        from dataclasses import replace
        discovery = mock.Mock(return_value={'ip': '192.168.1.54', 'host': 'Record-Blue.local'})
        for host in ['192.168.1.53', 'iMac-de-Sono-2.local']:
            target = targets.validate_target({'mode': 'remote', 'host': host})
            scope = {'load_target': lambda: target, 'OSCTransport': osc_transport.OSCTransport,
                     'discover_ableton_remote': discovery, 'dataclass_replace': replace}
            with mock.patch.object(osc_transport, 'resolve_ipv4_host', return_value='192.168.1.53') as resolve, mock.patch.object(osc_transport.udp_client, 'SimpleUDPClient') as client:
                exec(startup, scope)
                self.assertEqual(scope['ableton_target'], target)
                resolve.assert_called_once_with(host)
                client.assert_called_once_with('192.168.1.53', 11000)
                self.assertEqual(scope['ableton_transport'].reply_port, 11001)
                scope['ableton_transport'].send('/live/song/get/name')
                client.return_value.send_message.assert_called_once_with('/live/song/get/name', [])
        discovery.assert_not_called()


if __name__ == '__main__':
    unittest.main()
