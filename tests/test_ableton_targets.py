import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from ableton_targets import (
    MAX_CONFIG_SIZE,
    AbletonTarget,
    AbletonTargetError,
    default_profiles,
    load_profiles,
    load_target,
    local_target,
    save_profiles,
    save_target,
    select_active_profile,
    update_profile,
    validate_target,
)


class AbletonTargetTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.path = Path(self.temporary.name) / "config" / "network-config.json"

    def tearDown(self):
        self.temporary.cleanup()

    def write_payload(self, payload):
        self.path.parent.mkdir(mode=0o700)
        self.path.write_text(json.dumps(payload), encoding="utf-8")
        os.chmod(self.path, 0o600)

    def v1_payload(self, mode, host, send_port=11000, reply_port=11001):
        return {
            "schema_version": 1,
            "active_target": {
                "target_id": "primary",
                "mode": mode,
                "host": host,
                "send_port": send_port,
                "reply_port": reply_port,
            },
        }

    def test_missing_config_preserves_exact_local_defaults(self):
        profiles = load_profiles(self.path)
        self.assertEqual(profiles, default_profiles())
        self.assertEqual(load_target(self.path), local_target())
        self.assertFalse(self.path.exists())

    def test_local_mode_always_forces_loopback(self):
        target = validate_target({"mode": "local", "host": "192.168.1.20", "send_port": 11000, "reply_port": 11001})
        self.assertEqual(target.host, "127.0.0.1")

    def test_remote_mode_accepts_valid_ipv4_and_rejects_loopback(self):
        target = validate_target({"mode": "remote", "host": "192.168.50.10", "send_port": 11000, "reply_port": 11001})
        self.assertEqual(target, AbletonTarget(mode="remote", host="192.168.50.10"))
        for host in ("127.0.0.1", "127.22.3.4"):
            with self.subTest(host=host), self.assertRaises(AbletonTargetError):
                validate_target({"mode": "remote", "host": host})

    def test_invalid_address_ports_and_unexpected_keys_are_rejected(self):
        with self.assertRaises(AbletonTargetError):
            validate_target({"mode": "remote", "host": "not-an-ip"})
        with self.assertRaises(AbletonTargetError):
            validate_target({"mode": "remote", "host": "192.168.1.20", "send_port": 0})
        with self.assertRaises(AbletonTargetError):
            validate_target({"mode": "local", "unexpected": True})

    def test_v1_local_is_migrated_in_memory_without_remote_address_or_write(self):
        original = self.v1_payload("local", "127.0.0.1", 12000, 12001)
        self.write_payload(original)
        profiles = load_profiles(self.path)
        self.assertEqual(profiles.active_mode, "local")
        self.assertEqual((profiles.local.send_port, profiles.local.reply_port), (12000, 12001))
        self.assertIsNone(profiles.remote)
        self.assertEqual(json.loads(self.path.read_text()), original)

    def test_v1_remote_is_migrated_in_memory_with_exact_ports(self):
        original = self.v1_payload("remote", "192.168.10.42", 12000, 12001)
        self.write_payload(original)
        profiles = load_profiles(self.path)
        self.assertEqual(profiles.active_mode, "remote")
        self.assertEqual(profiles.local, local_target())
        self.assertEqual(profiles.remote.host, "192.168.10.42")
        self.assertEqual((profiles.remote.send_port, profiles.remote.reply_port), (12000, 12001))
        self.assertEqual(load_target(self.path), profiles.remote)
        self.assertEqual(json.loads(self.path.read_text()), original)

    def test_v2_round_trip_preserves_both_profiles_and_name(self):
        remote = AbletonTarget(mode="remote", host="192.168.50.10", send_port=12000, reply_port=12001)
        profiles = update_profile(default_profiles(), remote, name="Mac Blue", activate=True)
        profiles = update_profile(profiles, local_target(13000, 13001))
        save_profiles(profiles, self.path)
        loaded = load_profiles(self.path)
        self.assertEqual(loaded, profiles)
        self.assertEqual(loaded.remote_name, "Mac Blue")
        self.assertEqual(load_target(self.path), remote)
        self.assertEqual(self.path.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(list(self.path.parent.glob(".network-config-*")), [])

    def test_selecting_local_does_not_alter_remote_profile(self):
        remote = AbletonTarget(mode="remote", host="192.168.50.10", send_port=12000, reply_port=12001)
        profiles = update_profile(default_profiles(), remote, name="Mac Blue", activate=True)
        selected = select_active_profile(profiles, "local")
        self.assertEqual(selected.remote, remote)
        self.assertEqual(selected.remote_name, "Mac Blue")
        self.assertEqual(selected.active_target(), selected.local)

    def test_save_target_compatibility_updates_only_selected_profile(self):
        remote = AbletonTarget(mode="remote", host="192.168.50.10")
        save_target(remote, self.path)
        save_target(local_target(12000, 12001), self.path)
        profiles = load_profiles(self.path)
        self.assertEqual(profiles.active_mode, "local")
        self.assertEqual(profiles.remote, remote)
        self.assertEqual((profiles.local.send_port, profiles.local.reply_port), (12000, 12001))

    def test_unknown_schema_and_unexpected_v2_keys_are_rejected(self):
        self.write_payload({"schema_version": 99})
        with self.assertRaises(AbletonTargetError):
            load_profiles(self.path)
        payload = {"schema_version": 2, **default_profiles().to_dict(), "unexpected": True}
        self.path.write_text(json.dumps(payload), encoding="utf-8")
        with self.assertRaises(AbletonTargetError):
            load_profiles(self.path)

    def test_symlink_open_permissions_and_wrong_owner_are_rejected(self):
        self.path.parent.mkdir(mode=0o700)
        target = self.path.parent / "target.json"
        target.write_text("{}")
        self.path.symlink_to(target)
        with self.assertRaises(AbletonTargetError):
            load_profiles(self.path)
        self.path.unlink()
        save_profiles(default_profiles(), self.path)
        os.chmod(self.path, 0o644)
        with self.assertRaises(AbletonTargetError):
            load_profiles(self.path)
        os.chmod(self.path, 0o600)
        with mock.patch("ableton_targets.os.getuid", return_value=os.getuid() + 1):
            with self.assertRaises(AbletonTargetError):
                load_profiles(self.path)

    def test_oversized_file_is_rejected(self):
        self.path.parent.mkdir(mode=0o700)
        self.path.write_bytes(b" " * (MAX_CONFIG_SIZE + 1))
        os.chmod(self.path, 0o600)
        with self.assertRaises(AbletonTargetError):
            load_profiles(self.path)


if __name__ == "__main__":
    unittest.main()
