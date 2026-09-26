"""Server discovery is simulated: no live OSC/MIDI or network actions."""
import json
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from unittest import mock

import ableton_targets as targets
import launcher_control as launcher
from build_identity import BUILD_ID, IDENTITY_PROTOCOL_VERSION, SERVICE_NAME


def identity(**changes):
    return {"service": SERVICE_NAME, "build_id": BUILD_ID,
            "identity_protocol_version": IDENTITY_PROTOCOL_VERSION,
            "launch_id": "11111111-1111-4111-8111-111111111111",
            "server_instance_id": "22222222-2222-4222-8222-222222222222", **changes}


def response(payload):
    result = mock.MagicMock()
    result.__enter__.return_value.read.return_value = json.dumps(payload).encode()
    return result


class ParadisNetworkTests(unittest.TestCase):
    def setUp(self):
        launcher.cl_discovery_cache.clear()
        self.profiles = replace(targets.default_profiles(), cl_server_mode="paradis")
        self.names = mock.patch.object(launcher, "is_paradis_server_machine", return_value=False)
        self.names.start()
        self.addCleanup(self.names.stop)
        self.config = mock.patch.object(launcher, "load_profiles", return_value=self.profiles)
        self.config.start()
        self.addCleanup(self.config.stop)
        self.resolver = mock.patch.object(launcher, "resolve_ipv4_addresses", return_value=[]).start()
        self.addCleanup(mock.patch.stopall)
        self.opener = mock.patch.object(launcher.urllib.request, "build_opener").start().return_value
        self.opener.open.return_value = response(identity())

    def test_local_record_blue_uses_loopback_and_existing_ownership(self):
        with mock.patch.object(launcher, "is_paradis_server_machine", return_value=True), mock.patch.object(launcher, "tcp_ok", return_value=True), mock.patch.object(launcher, "current_identity_status", return_value=(identity(), {"valid": False, "code": "valid-unowned", "message": "Sans propriété"})):
            _, check, diagnostic = launcher.selected_cl_status()
        self.assertFalse(check["valid"])
        self.assertEqual(diagnostic["url"], "http://127.0.0.1:5050/")
        self.resolver.assert_not_called()
        self.opener.open.assert_not_called()

    def test_wired_precedes_dante_and_wifi(self):
        self.resolver.return_value = ["169.254.198.215", "192.168.1.54", "192.168.3.90"]
        _, check, diagnostic = launcher.selected_cl_status()
        self.assertTrue(check["valid"])
        self.assertEqual(diagnostic["address"], "192.168.3.90")
        self.resolver.assert_called_once_with("iMac-Record-Blue.local")
        self.assertEqual(self.opener.open.call_args.args[0], "http://192.168.3.90:5050/status")

    def test_known_wired_fallback_before_wifi(self):
        self.resolver.return_value = ["169.254.198.215", "192.168.1.54"]
        _, _, diagnostic = launcher.selected_cl_status()
        self.assertEqual(diagnostic["address"], "192.168.3.64")
        self.assertEqual(diagnostic["discovery"], "Adresse connue de secours")

    def test_dante_never_probed(self):
        self.resolver.return_value = ["169.254.198.215"]
        self.opener.open.side_effect = OSError("offline")
        _, check, _ = launcher.selected_cl_status()
        self.assertFalse(check["valid"])
        self.assertEqual([c.args[0] for c in self.opener.open.call_args_list], ["http://192.168.3.64:5050/status"])

    def test_invalid_identity_then_fallback(self):
        self.resolver.return_value = ["192.168.3.99"]
        self.opener.open.side_effect = [response({"service": "unrelated"}), response(identity())]
        _, check, diagnostic = launcher.selected_cl_status()
        self.assertTrue(check["valid"])
        self.assertEqual(diagnostic["address"], "192.168.3.64")

    def test_rejects_non_cl_missing_ids_and_incompatible_build(self):
        for value in ({}, [], identity(service="other"), identity(launch_id=None), identity(server_instance_id="bad"), identity(build_id="old"), identity(identity_protocol_version=99)):
            with self.subTest(value=value):
                launcher.cl_discovery_cache.clear()
                self.opener.open.return_value = response(value)
                _, check, _ = launcher.selected_cl_status()
                self.assertFalse(check["valid"])

    def test_refuses_redirect(self):
        self.assertIsNone(launcher.CLNoRedirect().redirect_request(None, None, 302, "", {}, "http://other/"))

    def test_manual_uses_only_configured_host(self):
        self.resolver.return_value = ["192.168.3.73"]
        manual = replace(self.profiles, cl_server_mode="manual", cl_server_host="Mac-mini-Monitor.local")
        _, check, diagnostic = launcher.selected_cl_status(manual)
        self.assertTrue(check["valid"])
        self.resolver.assert_called_once_with("Mac-mini-Monitor.local")
        self.assertEqual(diagnostic["address"], "192.168.3.73")

    def test_remote_never_starts_stops_or_adopts_local_process(self):
        with mock.patch.object(launcher, "current_identity_status") as local, mock.patch.object(launcher, "write_record") as write, mock.patch.object(launcher, "remove_record") as remove:
            for action in (launcher.start_web_server, launcher.stop_owned_server, launcher.adopt_claimable_server, launcher.stop_claimable_server):
                self.assertFalse(action()[0])
            self.assertTrue(launcher.ensure_selected_cl_server()[0])
        local.assert_not_called()
        write.assert_not_called()
        remove.assert_not_called()

    def test_remote_open_uses_validated_ip(self):
        with mock.patch.object(launcher, "open_remote_app_window", return_value="test") as opened:
            result = launcher.app.test_client().get('/open-ab')
        self.assertEqual(result.status_code, 200)
        self.assertEqual(opened.call_args.args[0], 'http://192.168.3.64:5050/ab?desktop=1&v=2.0.1')

    def test_invalid_server_cannot_open(self):
        self.opener.open.return_value = response({})
        with mock.patch.object(launcher, "open_remote_app_window") as opened:
            result = launcher.app.test_client().get('/open')
        self.assertEqual(result.status_code, 409)
        opened.assert_not_called()

    def test_save_server_preserves_osc_profiles(self):
        profiles = targets.update_profile(self.profiles, {"mode": "remote", "host": "iMac-de-Sono-2.local"}, name="Sono 2", activate=True)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "private" / "network-config.json"
            targets.save_profiles(profiles, path)
            self.assertEqual(targets.load_profiles(path), profiles)
            changed = targets.update_profile(targets.load_profiles(path), targets.local_target(), activate=True)
            targets.save_profiles(changed, path)
            restored = targets.load_profiles(path)
            self.assertEqual(restored.cl_server_mode, "paradis")
            self.assertEqual(restored.remote.host, "iMac-de-Sono-2.local")

    def test_server_route_only_updates_server_choice(self):
        with mock.patch.object(launcher, "save_profiles") as save:
            result = launcher.app.test_client().post('/network-config', json={"cl_server": {"mode": "manual", "host": "192.168.3.64"}})
        self.assertEqual(result.status_code, 200)
        saved = save.call_args.args[0]
        self.assertEqual(saved.local, self.profiles.local)
        self.assertEqual(saved.remote, self.profiles.remote)
        self.assertEqual(saved.active_mode, self.profiles.active_mode)

    def test_remote_osc_edit_is_refused(self):
        with mock.patch.object(launcher, "save_profiles") as save:
            result = launcher.app.test_client().post('/network-config', json={"mode": "local"})
        self.assertEqual(result.status_code, 409)
        save.assert_not_called()

    def test_local_valid_unowned_is_not_adopted(self):
        with mock.patch.object(launcher, "load_profiles", return_value=targets.default_profiles()), mock.patch.object(launcher, "tcp_ok", return_value=True), mock.patch.object(launcher, "current_identity_status", return_value=(identity(), {"valid": False, "code": "valid-unowned", "message": "Non possédé"})), mock.patch.object(launcher, "adopt_claimable_server") as adopt:
            self.assertFalse(launcher.ensure_selected_cl_server()[0])
        adopt.assert_not_called()

    def test_host_detection_case_and_trailing_dot(self):
        self.names.stop()
        with mock.patch.object(launcher.socket, "gethostname", return_value="IMAC-RECORD-BLUE.local."), mock.patch.object(launcher.socket, "getfqdn", return_value="other"), mock.patch.object(launcher.sys, "platform", "linux"):
            self.assertTrue(launcher.is_paradis_server_machine())

    def test_state_remote_readiness_uses_server_not_local_ports(self):
        self.opener.open.return_value = response(identity(set_ready=True, osc_transport={"connected": True}, ableton_target={"mode": "remote", "host": "iMac-de-Sono-2.local", "reply_port": 11001, "send_port": 11000}))
        with mock.patch.object(launcher, "port_used") as ports, mock.patch.object(launcher, "launcher_diagnostic_log"), mock.patch.object(launcher, "read_midi_console_state") as midi:
            result = launcher.app.test_client().get('/state').get_json()
        self.assertTrue(result['server_valid'])
        self.assertTrue(result['system_ready'])
        self.assertEqual(result['ableton_config']['host'], 'iMac-de-Sono-2.local')
        self.assertFalse(result['orphan_actions_available'])
        ports.assert_not_called()
        midi.assert_not_called()

    def test_local_orphan_diagnostics_are_preserved_without_validation(self):
        status = identity(server_process_id=321, started_at=1700000000)
        with mock.patch.object(launcher, "load_profiles", return_value=targets.default_profiles()), mock.patch.object(launcher, "tcp_ok", return_value=True), mock.patch.object(launcher, "current_identity_status", return_value=(status, {"valid": False, "code": "orphan-claimable", "message": "Récupérable"})), mock.patch.object(launcher, "port_used", return_value=False), mock.patch.object(launcher, "read_midi_console_state", return_value={}), mock.patch.object(launcher, "launcher_diagnostic_log"):
            result = launcher.app.test_client().get('/state').get_json()
        self.assertFalse(result['server_valid'])
        self.assertTrue(result['orphan_actions_available'])
        self.assertEqual(result['orphan_process_id'], 321)
        self.assertEqual(result['server_instance_id'], status['server_instance_id'])

    def test_ui_keeps_server_and_ableton_separate(self):
        page = launcher.app.test_client().get('/').get_data(as_text=True)
        for marker in ('id="clServerMode"', '>Paradis Latin<', '>Distant manuel<', 'id="abletonMode"', 'id="clServerDiagnostic"'):
            self.assertIn(marker, page)


if __name__ == '__main__':
    unittest.main()
