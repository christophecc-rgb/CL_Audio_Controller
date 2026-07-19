import os
import tempfile
import unittest
from pathlib import Path

from ableton_targets import (
    AbletonTarget,
    AbletonTargetError,
    load_target,
    local_target,
    save_target,
    validate_target,
)


class AbletonTargetTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.path = Path(self.temporary.name) / "config" / "network-config.json"

    def tearDown(self):
        self.temporary.cleanup()

    def test_missing_config_preserves_exact_local_defaults(self):
        self.assertEqual(load_target(self.path), local_target())
        self.assertEqual(local_target().host, "127.0.0.1")
        self.assertEqual(local_target().send_port, 11000)
        self.assertEqual(local_target().reply_port, 11001)

    def test_local_mode_always_forces_loopback(self):
        target = validate_target({"mode": "local", "host": "192.168.1.20", "send_port": 11000, "reply_port": 11001})
        self.assertEqual(target.host, "127.0.0.1")

    def test_remote_mode_accepts_valid_ipv4(self):
        target = validate_target({"mode": "remote", "host": "192.168.50.10", "send_port": 11000, "reply_port": 11001})
        self.assertEqual(target, AbletonTarget(mode="remote", host="192.168.50.10"))

    def test_invalid_address_and_ports_are_rejected(self):
        with self.assertRaises(AbletonTargetError):
            validate_target({"mode": "remote", "host": "not-an-ip"})
        with self.assertRaises(AbletonTargetError):
            validate_target({"mode": "remote", "host": "192.168.1.20", "send_port": 0})

    def test_round_trip_is_atomic_and_restrictive(self):
        target = AbletonTarget(mode="remote", host="192.168.50.10")
        save_target(target, self.path)
        self.assertEqual(load_target(self.path), target)
        self.assertEqual(self.path.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)

    def test_symlink_and_open_permissions_are_rejected(self):
        self.path.parent.mkdir(mode=0o700)
        target = self.path.parent / "target.json"
        target.write_text("{}")
        self.path.symlink_to(target)
        with self.assertRaises(AbletonTargetError):
            load_target(self.path)
        self.path.unlink()
        save_target(local_target(), self.path)
        os.chmod(self.path, 0o644)
        with self.assertRaises(AbletonTargetError):
            load_target(self.path)


if __name__ == "__main__":
    unittest.main()
