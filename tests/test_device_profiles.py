import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from device_profiles import (
    DeviceConfiguration,
    DeviceProfile,
    DeviceTestBench,
    FUTURE_PROTOCOLS,
    FUTURE_SIGNAL_TYPES,
    ProgramChangeSignalHandler,
    default_device_configuration,
    device_configuration_from_dict,
    load_device_configuration,
)


class DeviceProfileTests(unittest.TestCase):
    def setUp(self):
        self.configuration = default_device_configuration()
        self.cl5 = self.configuration.by_id("console_a")
        self.ql1 = self.configuration.by_id("console_b")

    def test_default_configuration_is_exactly_cl5_then_ql1(self):
        self.assertEqual([device.display_name for device in self.configuration.devices], ["CL5", "QL1"])
        self.assertEqual((self.cl5.legacy_key, self.ql1.legacy_key), ("cl5", "ql1"))
        self.assertTrue(all(device.enabled for device in self.configuration.devices))

    def test_default_channels_palettes_and_signal_are_unchanged(self):
        self.assertEqual((self.cl5.midi_channel, self.ql1.midi_channel), (1, 2))
        self.assertEqual(self.cl5.palette.to_dict(), {"base": "#C09AF2", "accent": "#9B6BD6"})
        self.assertEqual(self.ql1.palette.to_dict(), {"base": "#63C7D4", "accent": "#3E9EAC"})
        self.assertEqual({device.protocol for device in self.configuration.devices}, {"midi"})
        self.assertEqual({device.signal_type for device in self.configuration.devices}, {"program_change"})

    def test_internal_id_does_not_depend_on_display_name_or_channel(self):
        renamed = replace(self.ql1, display_name="DM7")
        self.assertEqual(renamed.id, "console_b")
        self.assertEqual(renamed.legacy_key, "ql1")
        self.assertEqual(renamed.midi_channel, 2)

    def test_multiple_ableton_aliases_are_supported_by_the_model(self):
        renamed = replace(
            self.ql1,
            ableton_track_aliases=("PGM CHANGE QL1", "PGM CHANGE DM7", "DM7 PROGRAM"),
        )
        self.assertEqual(len(renamed.ableton_track_aliases), 3)
        self.assertIn("PGM CHANGE QL1", renamed.ableton_track_aliases)

    def test_third_disabled_device_is_accepted_without_changing_defaults(self):
        third = replace(
            self.ql1, id="console_c", display_name="FUTURE", enabled=False,
            legacy_key=None, midi_channel=3,
        )
        configuration = DeviceConfiguration(devices=self.configuration.devices + (third,))
        self.assertEqual(len(configuration.devices), 3)
        self.assertFalse(configuration.by_id("console_c").enabled)
        self.assertEqual(configuration.by_legacy_key("cl5").midi_channel, 1)

    def test_visibility_is_configurable_per_interface(self):
        hidden = device_configuration_from_dict({"devices": [{
            **self.ql1.to_dict(),
            "visibility": {"show_control": False, "remote": True, "network_manager": False},
        }]}).devices[0]
        self.assertEqual(hidden.visibility.to_dict(), {
            "show_control": False, "remote": True, "network_manager": False,
        })

    def test_future_protocols_and_signal_types_are_declared_but_not_active(self):
        self.assertIn("osc", FUTURE_PROTOCOLS)
        self.assertTrue({"control_change", "note", "sysex", "osc_message"} <= FUTURE_SIGNAL_TYPES)
        future = replace(self.ql1, protocol="osc", signal_type="osc_message")
        self.assertFalse(future.supported)
        with self.assertRaises(NotImplementedError):
            DeviceTestBench(DeviceConfiguration(devices=(future,))).test_send(future.id, 1)

    def test_legacy_cl5_ql1_configuration_is_softly_adapted(self):
        migrated = device_configuration_from_dict({
            "cl5": {"display_name": "CL5"},
            "ql1": {"display_name": "DM7"},
        })
        self.assertEqual(migrated.by_legacy_key("cl5").id, "console_a")
        self.assertEqual(migrated.by_legacy_key("ql1").id, "console_b")
        self.assertEqual(migrated.by_legacy_key("ql1").midi_channel, 2)

    def test_missing_or_invalid_persistent_file_uses_safe_defaults(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "devices.json"
            self.assertEqual(load_device_configuration(path), self.configuration)
            path.write_text("not json", encoding="utf-8")
            self.assertEqual(load_device_configuration(path), self.configuration)

    def test_devices_list_round_trips_from_json_shape(self):
        payload = self.configuration.to_dict()
        restored = device_configuration_from_dict(json.loads(json.dumps(payload)))
        self.assertEqual(restored, self.configuration)

    def test_program_change_handler_is_pure_and_range_checked(self):
        self.assertEqual(ProgramChangeSignalHandler.parse_expected(0), 0)
        self.assertEqual(ProgramChangeSignalHandler.format_display_value(127), "128")
        self.assertTrue(ProgramChangeSignalHandler.compare(42, "42"))
        self.assertIsNone(ProgramChangeSignalHandler.parse_returned(128))

    def test_test_bench_state_never_mutates_production_state(self):
        production_state = {"cl5": {"expected_midi_program": 12}, "ql1": {"received": False}}
        before = json.loads(json.dumps(production_state))
        bench = DeviceTestBench(self.configuration)
        bench.test_send("console_a", 42)
        bench.test_receive("console_a", 42)
        self.assertTrue(bench.test_round_trip("console_a"))
        self.assertEqual(production_state, before)
        self.assertNotIn("cl5", bench.snapshot())


class DeviceProfileStatusCompatibilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("cl_device_profile_status_test", ROOT / "app.py")
        cls.module = importlib.util.module_from_spec(spec)
        with mock.patch.object(subprocess, "run") as mocked_run:
            mocked_run.return_value.stdout = ""
            sys.modules[spec.name] = cls.module
            spec.loader.exec_module(cls.module)

    def test_status_exposes_devices_and_preserves_historical_console_keys(self):
        with self.module.lock:
            snapshot = self.module.state_snapshot_locked()
        self.assertEqual([device["id"] for device in snapshot["devices"]], ["console_a", "console_b"])
        self.assertIn("cl5", snapshot["midi_console"])
        self.assertIn("ql1", snapshot["midi_console"])
        self.assertEqual(snapshot["devices"][0]["midi_channel"], 1)
        self.assertEqual(snapshot["devices"][1]["midi_channel"], 2)


if __name__ == "__main__":
    unittest.main()
