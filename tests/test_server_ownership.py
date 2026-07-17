import json
import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

import launcher_control as launcher
from build_identity import BUILD_ID, IDENTITY_PROTOCOL_VERSION, SERVICE_NAME
from server_ownership import (
    OwnershipRecordError,
    load_record,
    remove_record,
    write_record,
)


LAUNCH_ID = "11111111-1111-4111-8111-111111111111"
INSTANCE_ID = "22222222-2222-4222-8222-222222222222"


def record(**changes):
    value = {
        "schema_version": 1,
        "service": SERVICE_NAME,
        "identity_protocol_version": IDENTITY_PROTOCOL_VERSION,
        "launch_id": LAUNCH_ID,
        "server_instance_id": INSTANCE_ID,
        "build_id": BUILD_ID,
        "server_process_id": 1234,
        "server_started_at": 1700000000.0,
        "recorded_at": time.time(),
        "shutdown_token": "x" * 43,
    }
    value.update(changes)
    return value


def status(**changes):
    value = {
        "service": SERVICE_NAME,
        "identity_protocol_version": IDENTITY_PROTOCOL_VERSION,
        "launch_id": LAUNCH_ID,
        "server_instance_id": INSTANCE_ID,
        "build_id": BUILD_ID,
        "server_process_id": 1234,
        "started_at": 1700000000.0,
        "set_ready": True,
    }
    value.update(changes)
    return value


class OwnershipFileTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name) / "secure"
        self.path = self.directory / "server-ownership.json"

    def tearDown(self):
        self.temporary.cleanup()

    def test_atomic_record_has_restrictive_permissions_and_round_trips(self):
        write_record(record(), self.path)
        self.assertEqual(self.directory.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(load_record(self.path), record(recorded_at=load_record(self.path)["recorded_at"]))

    def test_symlink_is_refused(self):
        self.directory.mkdir(mode=0o700)
        target = self.directory / "target"
        target.write_text("{}")
        self.path.symlink_to(target)
        with self.assertRaises(OwnershipRecordError):
            load_record(self.path)

    def test_incorrect_file_permissions_are_refused(self):
        write_record(record(), self.path)
        os.chmod(self.path, 0o644)
        with self.assertRaises(OwnershipRecordError):
            load_record(self.path)
        with self.assertRaises(OwnershipRecordError):
            write_record(record(), self.path)

    def test_strict_schema_and_oversized_file_are_refused(self):
        write_record(record(), self.path)
        value = json.loads(self.path.read_text())
        value["unexpected"] = True
        self.path.write_text(json.dumps(value))
        os.chmod(self.path, 0o600)
        with self.assertRaises(OwnershipRecordError):
            load_record(self.path)
        self.path.write_bytes(b"x" * 9000)
        os.chmod(self.path, 0o600)
        with self.assertRaises(OwnershipRecordError):
            load_record(self.path)

    def test_safe_remove_never_follows_symlink(self):
        self.directory.mkdir(mode=0o700)
        target = self.directory / "target"
        target.write_text("keep")
        self.path.symlink_to(target)
        with self.assertRaises(OwnershipRecordError):
            remove_record(self.path)
        self.assertEqual(target.read_text(), "keep")


class OrphanClassificationTests(unittest.TestCase):
    def setUp(self):
        launcher.owned_server = None
        launcher.claimable_server = None
        launcher.ignored_orphan_instance_id = None

    def tearDown(self):
        launcher.owned_server = None
        launcher.claimable_server = None
        launcher.ignored_orphan_instance_id = None

    def classify(self, remote=None, local=None, alive=True, proof=True):
        with (
            mock.patch.object(launcher, "read_remote_state_diagnostic", return_value=remote or status()),
            mock.patch.object(launcher, "load_record", return_value=local),
            mock.patch.object(launcher, "process_alive", return_value=alive),
            mock.patch.object(launcher, "verify_server_ownership", return_value=(proof, "proof")),
        ):
            return launcher.current_identity_status()[1]

    def test_coherent_record_is_orphan_claimable(self):
        self.assertEqual(self.classify(local=record())["code"], "orphan-claimable")

    def test_compatible_instance_without_record_is_valid_unowned(self):
        self.assertEqual(self.classify(local=None)["code"], "valid-unowned")

    def test_stale_record_is_classified(self):
        self.assertEqual(self.classify(local=record(), alive=False)["code"], "stale-record")

    def test_wrong_token_or_changed_identity_is_not_claimable(self):
        self.assertEqual(self.classify(local=record(), proof=False)["code"], "identity-mismatch")
        self.assertEqual(
            self.classify(remote=status(server_instance_id="33333333-3333-4333-8333-333333333333"), local=record())["code"],
            "identity-mismatch",
        )

    def test_pid_reuse_does_not_override_instance_mismatch(self):
        remote = status(server_instance_id="33333333-3333-4333-8333-333333333333", server_process_id=1234)
        self.assertEqual(self.classify(remote=remote, local=record(), alive=True)["code"], "identity-mismatch")

    def test_different_build_and_unknown_service_are_distinct(self):
        self.assertEqual(self.classify(remote=status(build_id="other"), local=record())["code"], "different-build")
        self.assertEqual(self.classify(remote={"service": "other"}, local=record())["code"], "unknown-service")

    def test_explicit_adoption_reverifies_before_mutating_memory(self):
        launcher.claimable_server = record()
        with (
            mock.patch.object(launcher, "current_identity_status", return_value=(status(), {"code": "orphan-claimable"})),
            mock.patch.object(launcher, "verify_server_ownership", return_value=(True, "ok")),
        ):
            ok, _ = launcher.adopt_claimable_server()
        self.assertTrue(ok)
        self.assertTrue(launcher.owned_server["adopted"])
        self.assertIsNone(launcher.owned_server["process"])

    def test_identity_change_between_inspection_and_adoption_is_refused(self):
        launcher.claimable_server = record()
        changed = status(server_instance_id="33333333-3333-4333-8333-333333333333")
        with (
            mock.patch.object(launcher, "current_identity_status", return_value=(changed, {"code": "orphan-claimable"})),
            mock.patch.object(launcher, "verify_server_ownership", return_value=(False, "identity-mismatch")),
        ):
            ok, _ = launcher.adopt_claimable_server()
        self.assertFalse(ok)
        self.assertIsNone(launcher.owned_server)

    def test_failed_orphan_stop_keeps_record_and_does_not_terminate_pid(self):
        launcher.claimable_server = record()
        with (
            mock.patch.object(launcher, "current_identity_status", return_value=(status(), {"code": "orphan-claimable"})),
            mock.patch.object(launcher, "verify_server_ownership", side_effect=[(True, "ok"), (False, "token-invalid")]),
            mock.patch.object(launcher, "remove_record") as remove,
            mock.patch.object(launcher.os, "kill") as direct_kill,
        ):
            ok, _ = launcher.stop_claimable_server()
        self.assertFalse(ok)
        remove.assert_not_called()
        direct_kill.assert_not_called()


class NoGlobalTerminationTests(unittest.TestCase):
    def test_launcher_contains_no_global_process_termination(self):
        source = Path(launcher.__file__).read_text(encoding="utf-8")
        self.assertNotIn("pkill", source)
        self.assertNotIn("killall", source)
        self.assertNotIn("lsof -t", source)
        self.assertNotIn(".kill()", source)


if __name__ == "__main__":
    unittest.main()
