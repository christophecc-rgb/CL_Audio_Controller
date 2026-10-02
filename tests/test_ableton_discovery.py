"""Dedicated Ableton Bonjour tests; no LAN, processes or real configuration."""
import ast
import importlib.util
import sys
import types
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import ableton_discovery as discovery

ROOT = Path(__file__).resolve().parents[1]


def browse(name, index=4, action='Add'):
    return f'12:00:00.000 {action} 2 {index} local. _cl-ableton._udp. {name}\n'


def address(host, ip, index=4, action='Add'):
    return f'12:00:00.000 {action} 2 {index} {host}. {ip} 120\n'


class DiscoveryTests(unittest.TestCase):
    def test_one_and_multiple_readers_and_hostname(self):
        def run(args, timeout):
            if '-B' in args:
                return browse('Maison') + browse('Théâtre', 5) + browse('Maison', 5)
            if '-L' in args:
                host = 'MacBook-Pro.local' if args[args.index('-L') + 1] == 'Maison' else 'iMac-de-Sono-2.local'
                return f'can be reached at {host}.:11000 (interface 4)\n role=ableton protocol=abletonosc version=1'
            host = args[-1]
            return address(host, '192.168.1.138' if host.startswith('Mac') else '192.168.1.53', int(args[2]))
        result = discovery.scan_readers(run, lambda: ({4: 'en0', 5: 'en1'}, []))
        self.assertEqual(len(result['readers']), 2)
        mac = next(r for r in result['readers'] if r['host'] == 'MacBook-Pro.local')
        self.assertEqual(mac['interfaces'], ['en0', 'en1'])
        self.assertEqual(mac['addresses'], ['192.168.1.138'])
        self.assertEqual(mac['state'], 'resolved')
        self.assertEqual(mac['port'], 11000)

    def test_remove_and_wrong_service_and_disallowed_interface(self):
        output = browse('Gone') + browse('Gone', action='Rmv') + browse('Dante', 8) + browse('Present')
        output += browse('Not Ableton').replace('_cl-ableton', '_ssh')
        self.assertEqual(discovery.parse_browse(output, {4: 'en0'}), [(4, 'Present')])

    def test_autoip_invalid_and_cross_interface_addresses(self):
        output = ''.join(address('Mac.local', ip) for ip in ['169.254.1.2', '127.0.0.1', '224.0.0.1', '0.0.0.0', '192.168.1.5'])
        output += address('Mac.local', '192.168.3.5', 8)
        output += address('Other.local', '192.168.1.6')
        self.assertEqual(discovery.parse_addresses(output, 4, 'Mac.local'), ['192.168.1.5'])
        self.assertEqual(discovery.parse_addresses(output + address('Mac.local', '192.168.1.5', action='Rmv'), 4, 'Mac.local'), [])

    def test_role_and_protocol_required(self):
        for txt in ['', 'role=midi protocol=rtp', 'role=ableton protocol=other']:
            self.assertIsNone(discovery.parse_resolution('can be reached at Mac.local.:11000\n' + txt))
        self.assertIsNone(discovery.parse_resolution('can be reached at evil.example.:11000\nrole=ableton protocol=abletonosc'))

    def test_unresolved_is_not_available(self):
        row = dict(host='Mac.local', name='Mac', port=11000, addresses=[], interfaces=['en0'])
        self.assertEqual(discovery.merge_readers([row])[0]['state'], 'discovered')

    def test_named_dante_autoip_and_inactive_filtered(self):
        services = '\n'.join(f'({i+1}) {label}\n(Hardware Port: Ethernet, Device: en{i})' for i, label in enumerate(['Wi-Fi', 'Dante', 'Ethernet', 'USB']))
        interfaces = '\n'.join(f'en{i}: flags=1\n inet {ip}\n status: {status}' for i, (ip, status) in enumerate([('192.168.1.4', 'active'), ('192.168.3.4', 'active'), ('169.254.2.4', 'active'), ('192.168.4.4', 'inactive')]))
        with patch.object(discovery.socket, 'if_nametoindex', side_effect=lambda name: int(name[-1]) + 4):
            allowed, ignored = discovery.network_interfaces(lambda args, timeout: services if 'networksetup' in args[0] else interfaces)
        self.assertEqual(allowed, {4: 'en0'})
        self.assertEqual(len(ignored), 3)

    def test_short_cache_disappearance_network_change_and_failure(self):
        now = [0]
        scans = iter([{'readers': [{'host': 'Maison.local'}]}, {'readers': []}, {'readers': [{'host': 'Theatre.local'}]}])
        cache = discovery.DiscoveryCache(lambda: next(scans), lambda: now[0])
        self.assertEqual(cache.snapshot()['readers'][0]['host'], 'Maison.local')
        now[0] = 29
        self.assertEqual(cache.snapshot()['readers'][0]['host'], 'Maison.local')
        now[0] = 30
        self.assertEqual(cache.snapshot()['readers'], [])
        now[0] = 60
        self.assertEqual(cache.snapshot()['readers'][0]['host'], 'Theatre.local')
        now[0] = 90
        self.assertEqual(cache.snapshot()['readers'], [])

    def test_endpoint_read_only(self):
        from flask import Flask, jsonify
        tree = ast.parse((ROOT / 'launcher_control.py').read_text())
        route = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'ableton_discovery_status')
        app = Flask(__name__)
        cache = discovery.DiscoveryCache(lambda: {'readers': []})
        scope = {'app': app, 'jsonify': jsonify, 'ableton_discovery_cache': cache}
        exec(compile(ast.Module(body=[route], type_ignores=[]), '<route>', 'exec'), scope)
        response = app.test_client().get('/api/ableton-discovery')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers['Cache-Control'], 'no-store')
        self.assertEqual(response.json['readers'], [])



class InstallerTests(unittest.TestCase):
    def test_preserves_existing_extension_and_is_idempotent(self):
        spec = importlib.util.spec_from_file_location('install_bonjour', ROOT / 'INSTALLER_AbletonOSC/install_bonjour.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            source = 'from .manager import Manager\n\ndef create_instance(c_instance):\n    return Manager(c_instance)\n'
            (target / '__init__.py').write_text(source)
            manager = 'class Manager(object):\n    def disconnect(self): pass\n# custom readonly extension\n'
            (target / 'manager.py').write_text(manager)
            module.install(target)
            installed_init = (target / '__init__.py').read_bytes()
            (target / 'cl_bonjour.py').write_text('# old ctypes publisher')
            module.install(target)
            self.assertEqual((target / '__init__.py').read_bytes(), installed_init)
            self.assertEqual((target / 'cl_bonjour.py').read_bytes(),
                             (ROOT / 'INSTALLER_AbletonOSC/cl_bonjour.py').read_bytes())
            self.assertEqual((target / 'manager.py').read_text(), manager)
            self.assertEqual((target / '__init__.py.before-cl-bonjour').read_text(), source)
            self.assertIn('BonjourManager as Manager', (target / '__init__.py').read_text())


class PublisherTests(unittest.TestCase):
    def test_lifecycle_without_osc_or_lom_access(self):
        from unittest.mock import Mock
        class Manager:
            def __init__(self, c_instance):
                self.osc_server = c_instance
                self.scheduled = []
                self.disconnected = False
            def schedule_message(self, ticks, callback):
                self.scheduled.append((ticks, callback))
            def disconnect(self):
                self.disconnected = True
        package = types.ModuleType('fake_abletonosc')
        package.__path__ = []
        manager = types.ModuleType('fake_abletonosc.manager')
        manager.Manager = Manager
        with patch.dict(sys.modules, {'fake_abletonosc': package, 'fake_abletonosc.manager': manager}):
            spec = importlib.util.spec_from_file_location('fake_abletonosc.cl_bonjour', ROOT / 'INSTALLER_AbletonOSC/cl_bonjour.py')
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
        server = Mock()
        server._socket.fileno.return_value = 10
        server._socket.getsockname.return_value = ('0.0.0.0', 11000)
        with patch.object(module, 'Announcement') as announcement:
            instance = module.BonjourManager(server)
            announcement.assert_called_once_with(11000)
            announcement.return_value.poll.assert_called_once()
            instance.disconnect()
            announcement.return_value.close.assert_called_once()
            self.assertTrue(instance.disconnected)
            instance._cl_bonjour_tick()
            self.assertEqual(announcement.call_count, 1)
            server.send.assert_not_called()
        with patch.object(module, 'Announcement') as announcement:
            module.BonjourManager(None)
            announcement.assert_not_called()
            server._socket.getsockname.return_value = ('127.0.0.1', 11000)
            module.BonjourManager(server)
            announcement.assert_not_called()
        server._socket.getsockname.return_value = ('0.0.0.0', 11000)
        with patch.object(module, 'Announcement', side_effect=OSError('mock Bonjour failure')):
            instance = module.BonjourManager(server)
            self.assertEqual(len(instance.scheduled), 1)
            instance.disconnect()
            self.assertTrue(instance.disconnected)


if __name__ == '__main__':
    unittest.main()
