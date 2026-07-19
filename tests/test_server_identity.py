import importlib.util
import json
import subprocess
import sys
import unittest
import uuid
from pathlib import Path
from unittest import mock


PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

import build_identity
import ableton_targets
import launcher_control as launcher


LAUNCH_ID = "11111111-1111-4111-8111-111111111111"
INSTANCE_ID = "22222222-2222-4222-8222-222222222222"


def valid_status(**changes):
    payload = {
        "service": build_identity.SERVICE_NAME,
        "identity_protocol_version": build_identity.IDENTITY_PROTOCOL_VERSION,
        "launch_id": LAUNCH_ID,
        "server_instance_id": INSTANCE_ID,
        "build_id": build_identity.BUILD_ID,
        "server_process_id": 1234,
        "started_at": 1700000000.0,
        "set_ready": True,
        "set_generation": 7,
    }
    payload.update(changes)
    return payload


class FakeProcess:
    def __init__(self, pid=9876):
        self.pid = pid
        self.returncode = None
        self.terminated = False
        self.killed = False

    def poll(self):
        return self.returncode

    def wait(self, timeout=None):
        self.returncode = 0
        return 0

    def terminate(self):
        self.terminated = True

    def kill(self):
        self.killed = True


class ContextResponse:
    def read(self):
        return json.dumps({"owned": True, "server_instance_id": INSTANCE_ID}).encode()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class ServerIdentityTests(unittest.TestCase):
    def setUp(self):
        launcher.owned_server = None

    def tearDown(self):
        launcher.owned_server = None

    def test_valid_identity_ignores_pid_mismatch(self):
        result = launcher.validate_server_identity(
            valid_status(server_process_id=99999), LAUNCH_ID, INSTANCE_ID
        )
        self.assertTrue(result["valid"])

    def test_older_newer_and_unknown_protocol_are_distinct(self):
        older = launcher.validate_server_identity(valid_status(identity_protocol_version=0))
        newer = launcher.validate_server_identity(valid_status(identity_protocol_version=2))
        unknown = launcher.validate_server_identity(valid_status(identity_protocol_version=None))
        self.assertEqual(older["code"], "older-protocol")
        self.assertEqual(newer["code"], "newer-protocol")
        self.assertEqual(unknown["code"], "unknown-protocol")

    def test_old_instance_same_build_is_rejected(self):
        result = launcher.validate_server_identity(valid_status(), str(uuid.uuid4()))
        self.assertEqual(result["code"], "different-launch")

    def test_different_build_is_rejected(self):
        result = launcher.validate_server_identity(valid_status(build_id="other-build"))
        self.assertEqual(result["code"], "different-build")

    def test_unknown_service_and_missing_fields_are_rejected(self):
        self.assertEqual(
            launcher.validate_server_identity({"service": "other"})["code"],
            "unknown-service",
        )
        payload = valid_status()
        payload.pop("server_instance_id")
        self.assertEqual(launcher.validate_server_identity(payload)["code"], "invalid-identity")

    def test_normal_start_validates_spawned_server(self):
        process = FakeProcess()
        with (
            mock.patch.object(launcher.uuid, "uuid4", return_value=uuid.UUID(LAUNCH_ID)),
            mock.patch.object(launcher, "tcp_ok", side_effect=[False, True]),
            mock.patch.object(launcher, "read_remote_state_diagnostic", return_value=valid_status()),
            mock.patch.object(launcher.subprocess, "Popen", return_value=process),
            mock.patch.object(launcher, "load_record", return_value=None),
            mock.patch.object(launcher, "write_record"),
        ):
            ok, _ = launcher.start_web_server(timeout=0.2)
        self.assertTrue(ok)
        self.assertEqual(launcher.owned_server["server_instance_id"], INSTANCE_ID)

    def test_existing_unknown_service_is_not_killed_or_reused(self):
        with (
            mock.patch.object(launcher, "tcp_ok", return_value=True),
            mock.patch.object(launcher, "read_remote_state_diagnostic", return_value={"service": "other"}),
            mock.patch.object(launcher.subprocess, "Popen") as popen,
        ):
            ok, message = launcher.start_web_server()
        self.assertFalse(ok)
        self.assertIn("inconnu", message.lower())
        popen.assert_not_called()

    def test_owned_server_is_reused(self):
        process = FakeProcess()
        launcher.owned_server = {
            "process": process,
            "launch_id": LAUNCH_ID,
            "server_instance_id": INSTANCE_ID,
            "shutdown_token": "secret",
            "build_id": build_identity.BUILD_ID,
        }
        with mock.patch.object(launcher, "read_remote_state_diagnostic", return_value=valid_status()):
            ok, _ = launcher.start_web_server()
        self.assertTrue(ok)

    def test_unowned_server_cannot_be_stopped(self):
        ok, message = launcher.stop_owned_server()
        self.assertFalse(ok)
        self.assertIn("Aucune instance", message)

    def test_owned_server_receives_authenticated_graceful_shutdown(self):
        process = FakeProcess()
        launcher.owned_server = {
            "process": process,
            "launch_id": LAUNCH_ID,
            "server_instance_id": INSTANCE_ID,
            "shutdown_token": "secret",
            "build_id": build_identity.BUILD_ID,
        }
        with (
            mock.patch.object(launcher, "read_remote_state_diagnostic", return_value=valid_status()),
            mock.patch.object(launcher, "verify_server_ownership", return_value=(True, "ownership-verified")),
            mock.patch.object(launcher, "process_alive", return_value=False),
            mock.patch.object(launcher, "tcp_ok", return_value=False),
            mock.patch.object(launcher, "port_used", return_value=False),
            mock.patch.object(launcher, "remove_record"),
            mock.patch.object(launcher.urllib.request, "urlopen", return_value=ContextResponse()) as request,
        ):
            ok, _ = launcher.stop_owned_server()
        self.assertTrue(ok)
        request.assert_called_once()
        self.assertTrue(process.terminated)
        self.assertFalse(process.killed)

    def test_server_valid_and_system_ready_are_distinct(self):
        launcher.owned_server = {
            "process": FakeProcess(),
            "launch_id": LAUNCH_ID,
            "server_instance_id": INSTANCE_ID,
            "shutdown_token": "secret",
            "build_id": build_identity.BUILD_ID,
        }
        with (
            mock.patch.object(launcher, "tcp_ok", return_value=True),
            mock.patch.object(launcher, "port_used", return_value=True),
            mock.patch.object(launcher, "read_remote_state_diagnostic", return_value=valid_status(set_ready=False)),
        ):
            payload = launcher.app.test_client().get("/state").get_json()
        self.assertTrue(payload["server_valid"])
        self.assertFalse(payload["live_set_ready"])
        self.assertFalse(payload["system_ready"])

    def test_valid_ready_server_with_osc_return_is_system_ready(self):
        launcher.owned_server = {
            "process": FakeProcess(),
            "launch_id": LAUNCH_ID,
            "server_instance_id": INSTANCE_ID,
            "shutdown_token": "secret",
            "build_id": build_identity.BUILD_ID,
        }
        with (
            mock.patch.object(launcher, "tcp_ok", return_value=True),
            mock.patch.object(launcher, "port_used", return_value=True),
            mock.patch.object(launcher, "read_remote_state_diagnostic", return_value=valid_status(set_ready=True)),
        ):
            payload = launcher.app.test_client().get("/state").get_json()
        self.assertTrue(payload["server_valid"])
        self.assertTrue(payload["live_set_ready"])
        self.assertTrue(payload["system_ready"])


class ServerStatusContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("identity_app_test", PROJECT_ROOT / "app.py")
        cls.module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = cls.module
        spec.loader.exec_module(cls.module)

    def test_status_exposes_identity_and_uptime(self):
        payload = self.module.app.test_client().get("/status").get_json()
        self.assertEqual(payload["service"], build_identity.SERVICE_NAME)
        self.assertEqual(payload["identity_protocol_version"], 1)
        self.assertEqual(payload["build_id"], build_identity.BUILD_ID)
        uuid.UUID(payload["server_instance_id"])
        self.assertIsInstance(payload["started_at"], float)
        self.assertGreaterEqual(payload["uptime_ms"], 0)

    def test_shutdown_rejects_unowned_request(self):
        response = self.module.app.test_client().post("/shutdown")
        self.assertEqual(response.status_code, 403)

    def test_ownership_proof_returns_no_secret(self):
        old_values = (self.module.LAUNCH_ID, self.module.SHUTDOWN_TOKEN)
        self.module.LAUNCH_ID = LAUNCH_ID
        self.module.SHUTDOWN_TOKEN = "s" * 43
        try:
            response = self.module.app.test_client().post(
                "/ownership/verify",
                headers={
                    "X-CL-Launch-ID": LAUNCH_ID,
                    "X-CL-Server-Instance-ID": self.module.SERVER_INSTANCE_ID,
                    "X-CL-Build-ID": build_identity.BUILD_ID,
                    "X-CL-Shutdown-Token": "s" * 43,
                },
            )
            payload = response.get_json()
            self.assertTrue(payload["owned"])
            self.assertNotIn("token", json.dumps(payload).lower())
            refused = self.module.app.test_client().post(
                "/ownership/verify",
                headers={
                    "X-CL-Launch-ID": LAUNCH_ID,
                    "X-CL-Server-Instance-ID": self.module.SERVER_INSTANCE_ID,
                    "X-CL-Build-ID": build_identity.BUILD_ID,
                    "X-CL-Shutdown-Token": "wrong",
                },
            ).get_json()
            self.assertFalse(refused["owned"])
        finally:
            self.module.LAUNCH_ID, self.module.SHUTDOWN_TOKEN = old_values

    def test_transport_connection_test_does_not_mutate_business_state(self):
        with self.module.lock:
            before = self.module.state_snapshot_locked()
        with mock.patch.object(
            self.module.ableton_transport,
            "query",
            return_value=(12, 1),
        ):
            response = self.module.app.test_client().post("/transport/test")
        with self.module.lock:
            after = self.module.state_snapshot_locked()
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.get_json()["ok"])
        for key in ("set_generation", "set_ready", "current_set_id", "scenes"):
            self.assertEqual(after[key], before[key])


class NetworkConfigurationRouteTests(unittest.TestCase):
    def test_local_configuration_without_server_is_saved_without_restart(self):
        previous = ableton_targets.AbletonTarget(mode="remote", host="192.168.50.10")
        with (
            mock.patch.object(launcher, "load_target", return_value=previous),
            mock.patch.object(launcher, "save_target") as save,
            mock.patch.object(launcher, "tcp_ok", return_value=False),
            mock.patch.object(launcher, "start_web_server") as start,
        ):
            response = launcher.app.test_client().post(
                "/network-config",
                json={"mode": "local", "host": "192.168.50.99", "send_port": 11000, "reply_port": 11001},
            )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(save.call_args.args[0].host, "127.0.0.1")
        start.assert_not_called()

    def test_configuration_change_restarts_only_owned_server(self):
        previous = ableton_targets.local_target()
        with (
            mock.patch.object(launcher, "load_target", return_value=previous),
            mock.patch.object(launcher, "save_target") as save,
            mock.patch.object(launcher, "tcp_ok", return_value=True),
            mock.patch.object(launcher, "current_identity_status", return_value=(valid_status(), {"valid": True})),
            mock.patch.object(launcher, "stop_owned_server", return_value=(True, "stopped")) as stop,
            mock.patch.object(launcher, "start_web_server", return_value=(True, "started")) as start,
        ):
            response = launcher.app.test_client().post(
                "/network-config",
                json={"mode": "remote", "host": "192.168.50.10", "send_port": 11000, "reply_port": 11001},
            )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(save.call_args.args[0].host, "192.168.50.10")
        stop.assert_called_once_with()
        start.assert_called_once_with()

    def test_configuration_refuses_unowned_active_server(self):
        with (
            mock.patch.object(launcher, "load_target", return_value=ableton_targets.local_target()),
            mock.patch.object(launcher, "save_target") as save,
            mock.patch.object(launcher, "tcp_ok", return_value=True),
            mock.patch.object(launcher, "current_identity_status", return_value=(valid_status(), {"valid": False})),
        ):
            response = launcher.app.test_client().post(
                "/network-config",
                json={"mode": "remote", "host": "192.168.50.10", "send_port": 11000, "reply_port": 11001},
            )
        self.assertEqual(response.status_code, 409)
        save.assert_not_called()


if __name__ == "__main__":
    unittest.main()
