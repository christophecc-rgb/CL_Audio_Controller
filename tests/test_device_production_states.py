import importlib.util
import json
import subprocess
import sys
import tempfile
import time
import unittest
from dataclasses import replace
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from device_profiles import DeviceConfiguration, default_device_configuration, new_disabled_device


def load_app_module():
    spec = importlib.util.spec_from_file_location("cl_device_production_state_test", ROOT / "app.py")
    module = importlib.util.module_from_spec(spec)
    with mock.patch.object(subprocess, "run") as mocked_run:
        mocked_run.return_value.stdout = ""
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
    return module


class GenericDeviceProductionStateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = load_app_module()
        defaults = default_device_configuration()
        third = replace(
            new_disabled_device(defaults),
            enabled=True,
            display_name="DM7 FOH",
            ableton_track_aliases=("PGM CHANGE DM7", "DM7 PROGRAM", "CONSOLE C"),
            library=None,
        )
        cls.configuration = replace(defaults, devices=defaults.devices + (third,))

    def setUp(self):
        self.configuration_patch = mock.patch.object(
            self.app, "DEVICE_CONFIGURATION", self.configuration,
        )
        self.configuration_patch.start()
        self.addCleanup(self.configuration_patch.stop)
        with self.app.lock:
            self.app.state["ableton_midi_output"] = {"cl5": None, "ql1": None}
            self.app.state["console_scene_map"] = {"cl5": {}, "ql1": {}, "device_3": {}}
            self.app.state["console_scene_libraries"] = {"cl5": {}, "ql1": {}}
            self.app.state["console_title_offsets"] = {"cl5": 0, "ql1": 0}

    def test_aliases_resolve_to_one_device_and_scene_map_is_generic(self):
        aliases = self.app.ableton_alias_device_map()
        for alias in ("pgm change dm7", "dm7 program", "console c"):
            self.assertEqual(aliases[alias], "device_3")
        mapping = self.app.build_console_scene_map(
            ["Main", "DM7 PROGRAM", "PGM CHANGE CL5", "PGM CHANGE QL1"],
            {
                0: ["SCENE A"], 1: ["PGM CHANGE 43"],
                2: ["PGM CHANGE 11"], 3: ["PGM CHANGE 12"],
            },
            1,
        )
        self.assertEqual(mapping["device_3"][42][0]["title"], "SCENE A")
        self.assertIs(mapping["console_a"], mapping["cl5"])
        self.assertIs(mapping["console_b"], mapping["ql1"])

    def test_repeated_and_rapid_program_changes_create_new_expected_activations(self):
        self.assertTrue(self.app.record_ableton_midi_output("DM7 PROGRAM", 42, 100.0))
        first = dict(self.app.state["ableton_midi_output"]["device_3"])
        self.assertTrue(self.app.record_ableton_midi_output("CONSOLE C", 42, 101.0))
        repeated = dict(self.app.state["ableton_midi_output"]["device_3"])
        self.assertTrue(self.app.record_ableton_midi_output("device_3", 43, 101.01))
        changed = dict(self.app.state["ableton_midi_output"]["device_3"])
        self.assertEqual(first["expected_midi_program"], 42)
        self.assertEqual(repeated["expected_midi_program"], 42)
        self.assertEqual(repeated["expected_activated_at"], 101.0)
        self.assertEqual(changed["expected_midi_program"], 43)
        self.assertEqual(changed["expected_activated_at"], 101.01)

    def test_device_3_expected_is_published_without_inventing_returned(self):
        now = time.time()
        self.assertTrue(self.app.record_ableton_midi_output("PGM CHANGE DM7", 42, now))
        with self.app.lock:
            self.app.state["set_ready"] = True
            self.app.state["set_generation"] = 7
            self.app.state["play_mode"] = "session"
            self.app.state["playing_scene"] = 0
            self.app.state["playing_scene_name"] = "SCENE A"
            self.app.state["expected_scene_signature"] = (7, "session", 0)
            self.app.state["expected_activated_at"] = now
            self.app.state["console_scene_map"]["device_3"] = {
                42: [{"scene_index": 0, "midi_program": 42, "program": 43, "title": "SCENE A"}],
            }
        payload = {
            "service": "cl-midi-console-monitor",
            "updated_at": now,
            "return_mode": "console_return",
            "expected_monitor_source": "Gestionnaire IAC Bus 1",
            "expected_monitor_status": 0,
            "cl5": {"received": False},
            "ql1": {"received": False},
        }
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "midi-state.json"
            path.write_text(json.dumps(payload), encoding="utf-8")
            with self.app.lock, mock.patch.object(self.app, "MIDI_CONSOLE_STATE_PATH", path):
                snapshot = self.app.state_snapshot_locked()
        device = snapshot["device_states"]["device_3"]
        self.assertEqual([item["id"] for item in snapshot["devices"]], [
            "console_a", "console_b", "device_3",
        ])
        self.assertEqual(device["midi_channel"], 3)
        self.assertEqual(device["expected_midi_program"], 42)
        self.assertEqual(device["expected_scene_memory"], 43)
        self.assertEqual(device["expected_activated_at"], now)
        self.assertIsNone(device["returned_midi_program"])
        self.assertIsNone(device["returned_scene_memory"])
        self.assertEqual(device["validation_status"], "waiting")
        self.assertFalse(device["confirmed"])
        self.assertFalse(device["matched"])
        self.assertEqual(
            snapshot["device_states"]["console_a"]["expected_midi_program"],
            snapshot["midi_console"]["cl5"]["expected_midi_program"],
        )
        self.assertEqual(
            snapshot["device_states"]["console_b"]["expected_midi_program"],
            snapshot["midi_console"]["ql1"]["expected_midi_program"],
        )

    def test_real_native_device_3_return_confirms_or_mismatches_numeric_expected(self):
        returned_program = 42
        for expected_program, expected_status in ((42, "confirmed"), (41, "mismatch")):
            with self.subTest(expected_status=expected_status):
                now = time.time()
                with self.app.lock:
                    self.app.state["set_ready"] = True
                    self.app.state["set_generation"] = 8
                    self.app.state["play_mode"] = "session"
                    self.app.state["playing_scene"] = 0
                    self.app.state["playing_scene_name"] = "SCENE A"
                    self.app.state["expected_scene_signature"] = (8, "session", 0)
                    self.app.state["expected_activated_at"] = now - 0.1
                payload = {
                    "service": "cl-midi-console-monitor",
                    "updated_at": now,
                    "return_mode": "console_return",
                    "expected_monitor_source": "Gestionnaire IAC Bus 1",
                    "expected_monitor_status": 0,
                    "cl5": {"received": False},
                    "ql1": {"received": False},
                    "expected_devices": {
                        "device_3": {
                            "midi_program": expected_program,
                            "expected_midi_program": expected_program,
                            "scene_memory": expected_program + 1,
                            "expected_scene_memory": expected_program + 1,
                            "received_at": now - 0.1,
                            "expected_activated_at": now - 0.1,
                            "source": "ableton_iac_output",
                        },
                    },
                    "returned_devices": {
                        "device_3": {
                            "midi_program": returned_program,
                            "scene_memory": returned_program + 1,
                            "received_at": now,
                            "source": "physical_midi",
                        },
                    },
                }
                with tempfile.TemporaryDirectory() as temporary:
                    path = Path(temporary) / "midi-state.json"
                    path.write_text(json.dumps(payload), encoding="utf-8")
                    with self.app.lock, mock.patch.object(self.app, "MIDI_CONSOLE_STATE_PATH", path):
                        snapshot = self.app.state_snapshot_locked()
                device = snapshot["device_states"]["device_3"]
                self.assertEqual(device["returned_midi_program"], returned_program)
                self.assertEqual(device["returned_scene_memory"], returned_program + 1)
                self.assertEqual(device["returned_received_at"], now)
                self.assertEqual(device["returned_program_source"], "physical_midi")
                self.assertEqual(device["validation_status"], expected_status)
                self.assertEqual(device["confirmed"], expected_status == "confirmed")

    def test_native_expected_device_3_is_numeric_without_any_return(self):
        now = time.time()
        payload = {
            "service": "cl-midi-console-monitor",
            "updated_at": now,
            "return_mode": "console_return",
            "expected_monitor_source": "Gestionnaire IAC Bus 1",
            "expected_monitor_status": 0,
            "cl5": {"received": False},
            "ql1": {"received": False},
            "expected_devices": {
                "device_3": {
                    "midi_program": 49,
                    "scene_memory": 50,
                    "received_at": now,
                    "expected_activated_at": now,
                    "source": "ableton_iac_output",
                },
            },
        }
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "midi-state.json"
            path.write_text(json.dumps(payload), encoding="utf-8")
            with self.app.lock, mock.patch.object(self.app, "MIDI_CONSOLE_STATE_PATH", path):
                snapshot = self.app.state_snapshot_locked()
        device = snapshot["device_states"]["device_3"]
        self.assertEqual(device["expected_midi_program"], 49)
        self.assertEqual(device["expected_scene_memory"], 50)
        self.assertEqual(device["expected_activated_at"], now)
        self.assertIsNone(device["returned_midi_program"])
        self.assertEqual(device["validation_status"], "waiting")
        self.assertFalse(device["confirmed"])

    def test_real_return_without_expected_is_unavailable_not_confirmed(self):
        device = self.app.build_device_state(
            self.configuration.by_id("device_3"),
            None,
            {"returned_midi_program": 42, "returned_received_at": 100.0},
            now=100.1,
        )
        self.assertEqual(device["validation_status"], "unavailable")
        self.assertFalse(device["confirmed"])
        self.assertFalse(device["mismatch"])

    def test_disabled_and_unsupported_devices_are_not_production_states(self):
        disabled = replace(self.configuration.by_id("device_3"), enabled=False)
        unsupported = replace(
            disabled, id="device_4", enabled=True, protocol="osc", signal_type="osc_message",
        )
        configuration = DeviceConfiguration(
            devices=self.configuration.devices[:2] + (disabled, unsupported),
        )
        with mock.patch.object(self.app, "DEVICE_CONFIGURATION", configuration):
            self.assertEqual(
                [device.id for device in self.app.production_device_profiles()],
                ["console_a", "console_b"],
            )

    def test_control_change_and_note_are_published_but_not_routed_in_production(self):
        base = self.configuration.by_id("device_3")
        control = replace(
            base, id="lighting_control", midi_channel=4,
            signal_type="control_change", ableton_track_aliases=(), library=None,
        )
        note = replace(
            base, id="sampler_notes", midi_channel=5,
            signal_type="note", ableton_track_aliases=(), library=None,
        )
        configuration = replace(
            self.configuration, devices=self.configuration.devices + (control, note),
        )
        with mock.patch.object(self.app, "DEVICE_CONFIGURATION", configuration):
            routed = [device.id for device in self.app.production_device_profiles()]
            with self.app.lock:
                snapshot = self.app.state_snapshot_locked()

        self.assertEqual(routed, ["console_a", "console_b", "device_3"])
        devices = {device["id"]: device for device in snapshot["devices"]}
        self.assertFalse(devices["lighting_control"]["production_supported"])
        self.assertFalse(devices["sampler_notes"]["production_supported"])
        self.assertIsNone(devices["lighting_control"]["library"])
        self.assertIsNone(devices["sampler_notes"]["library"])


if __name__ == "__main__":
    unittest.main()
