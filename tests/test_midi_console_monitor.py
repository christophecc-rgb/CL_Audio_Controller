import json
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "create_midi_console_monitor.py"
DISPLAY = ROOT / "M4L" / "Devices" / "CL MIDI Console Monitor" / "CLMidiConsoleDisplay.js"
CONFIRMATION = ROOT / "M4L" / "Devices" / "CL MIDI Console Monitor" / "CLMidiConsoleConfirmation.js"


def load_amxd(path):
    raw = path.read_bytes()
    assert raw[:4] == b"ampf"
    length = struct.unpack("<I", raw[28:32])[0]
    return json.loads(raw[32:32 + length].decode("utf-8"))


class MidiConsoleMonitorTests(unittest.TestCase):
    def build_device(self):
        temporary = tempfile.TemporaryDirectory()
        output = Path(temporary.name)
        subprocess.run(
            ["python3", str(SCRIPT), "--output-dir", str(output)],
            check=True,
            capture_output=True,
            text=True,
        )
        return temporary, output

    def test_generates_source_and_installable_container(self):
        temporary, output = self.build_device()
        self.addCleanup(temporary.cleanup)
        maxpat = output / "CL MIDI Console Monitor.maxpat"
        amxd = output / "CL MIDI Console Monitor.amxd"
        self.assertTrue(maxpat.exists())
        self.assertTrue(amxd.exists())
        self.assertEqual(json.loads(maxpat.read_text()), load_amxd(amxd))
        raw = amxd.read_bytes()
        self.assertEqual(raw[8:12], b"mmmm")
        self.assertEqual(raw[12:16], b"meta")
        self.assertEqual(struct.unpack("<I", raw[20:24])[0], 0)
        self.assertEqual(raw[32:33], b"{")
        self.assertEqual(load_amxd(amxd)["patcher"]["project"]["amxdtype"], 1835887981)

    def test_midi_is_forwarded_unchanged_and_tapped(self):
        temporary, output = self.build_device()
        self.addCleanup(temporary.cleanup)
        patcher = json.loads((output / "CL MIDI Console Monitor.maxpat").read_text())["patcher"]
        lines = [item["patchline"] for item in patcher["lines"]]
        self.assertIn({"source": ["midi-in", 0], "destination": ["midi-out", 0], "order": 0}, lines)
        self.assertIn({"source": ["midi-in", 0], "destination": ["midi-parse", 0], "order": 1}, lines)

    def test_only_program_change_feeds_the_dashboard(self):
        temporary, output = self.build_device()
        self.addCleanup(temporary.cleanup)
        patcher = json.loads((output / "CL MIDI Console Monitor.maxpat").read_text())["patcher"]
        boxes = {item["box"]["id"]: item["box"] for item in patcher["boxes"]}
        lines = [item["patchline"] for item in patcher["lines"]]
        parse_lines = [line for line in lines if line["source"][0] == "midi-parse"]
        self.assertEqual({line["source"][1] for line in parse_lines}, {3})

        # Max's gate receives its selector in the left inlet and event data in
        # the right inlet. Reversing these wires makes it reject "CC"/"PGM".
        self.assertIn({"source": ["midi-parse", 3], "destination": ["event-gate", 1]}, lines)
        self.assertIn({"source": ["role-index", 0], "destination": ["event-gate", 0]}, lines)
        self.assertNotIn("cc-label", boxes)

    def test_command_and_return_roles_feed_two_physical_console_rows(self):
        temporary, output = self.build_device()
        self.addCleanup(temporary.cleanup)
        patcher = json.loads((output / "CL MIDI Console Monitor.maxpat").read_text())["patcher"]
        boxes = {item["box"]["id"]: item["box"] for item in patcher["boxes"]}
        lines = [item["patchline"] for item in patcher["lines"]]
        self.assertEqual(boxes["role-menu"]["items"], [
            "CL5", "QL1 CC", "QL1 PGM", "CL5 retour", "QL1 retour",
        ])
        self.assertEqual(boxes["event-gate"]["text"], "gate 5")
        self.assertEqual(boxes["display-cl5"]["presentation"], 1)
        self.assertEqual(boxes["display-ql1"]["presentation"], 1)
        self.assertNotIn("display-ql1-cc", boxes)
        self.assertNotIn("display-ql1-pgm", boxes)
        self.assertEqual(boxes["send-ql1-cc"]["text"], "s CL_MIDI_MON_QL1")
        self.assertEqual(boxes["send-ql1-pgm"]["text"], "s CL_MIDI_MON_QL1")
        for identifier in ("panel-cl5", "panel-ql1"):
            self.assertEqual(boxes[identifier]["background"], 1)
        for identifier in ("display-cl5", "display-ql1"):
            display = boxes[identifier]
            self.assertEqual(display["fontface"], 1)
            self.assertEqual(display["border"], 0)
            self.assertEqual(display["textcolor"][3], 1.0)
            self.assertEqual(display["bgcolor"][3], 1.0)
            self.assertGreater(sum(display["textcolor"][:3]), sum(display["bgcolor"][:3]))
        self.assertEqual(boxes["display-cl5"]["textcolor"], boxes["label-cl5"]["textcolor"])
        self.assertEqual(boxes["display-ql1"]["textcolor"], boxes["label-ql1"]["textcolor"])
        self.assertEqual(patcher["openinpresentation"], 1)
        self.assertEqual(boxes["subtitle"]["presentation"], 0)
        self.assertEqual(boxes["midi-status"]["presentation"], 1)
        self.assertEqual(boxes["midi-status"]["text"], "MIDI · en attente")
        self.assertEqual(boxes["logo"]["pic"], "paradis_latin_logo.jpg")
        self.assertEqual(boxes["midi-led"]["presentation"], 1)
        self.assertEqual(boxes["midi-led"]["blinkcolor"], [0.20, 0.95, 0.42, 1.0])
        for outlet in (0, 1, 2, 3, 4):
            self.assertIn(
                {"source": ["event-gate", outlet], "destination": ["midi-led", 0]},
                lines,
            )
        self.assertLessEqual(boxes["panel-cl5"]["presentation_rect"][1], 38.0)
        self.assertLessEqual(boxes["midi-status"]["presentation_rect"][1], 104.0)

    def test_console_returns_validate_the_requested_memory(self):
        temporary, output = self.build_device()
        self.addCleanup(temporary.cleanup)
        patcher = json.loads((output / "CL MIDI Console Monitor.maxpat").read_text())["patcher"]
        boxes = {item["box"]["id"]: item["box"] for item in patcher["boxes"]}
        lines = [item["patchline"] for item in patcher["lines"]]
        self.assertEqual(boxes["request-cl5"]["text"], "s CL_MIDI_MON_CL5_REQUEST")
        self.assertEqual(boxes["request-ql1-cc"]["text"], "s CL_MIDI_MON_QL1_REQUEST")
        self.assertEqual(boxes["request-ql1-pgm"]["text"], "s CL_MIDI_MON_QL1_REQUEST")
        self.assertEqual(boxes["confirm-cl5"]["text"], "s CL_MIDI_MON_CL5_CONFIRM")
        self.assertEqual(boxes["confirm-ql1"]["text"], "s CL_MIDI_MON_QL1_CONFIRM")
        self.assertIn({"source": ["event-gate", 3], "destination": ["confirm-cl5", 0]}, lines)
        self.assertIn({"source": ["event-gate", 4], "destination": ["confirm-ql1", 0]}, lines)
        self.assertEqual(boxes["confirmation-cl5"]["presentation"], 1)
        self.assertEqual(boxes["confirmation-ql1"]["presentation"], 1)
        source = CONFIRMATION.read_text()
        self.assertIn("confirmedProgram === expectedProgram", source)
        self.assertIn('["✓", "CHARGÉE"', source)
        self.assertIn('["⚠", "REÇUE"', source)

    def test_role_is_initialized_when_the_device_is_loaded(self):
        temporary, output = self.build_device()
        self.addCleanup(temporary.cleanup)
        patcher = json.loads((output / "CL MIDI Console Monitor.maxpat").read_text())["patcher"]
        boxes = {item["box"]["id"]: item["box"] for item in patcher["boxes"]}
        lines = [item["patchline"] for item in patcher["lines"]]
        self.assertEqual(boxes["role-default"]["text"], "loadmess 1")
        self.assertNotIn("role-get", boxes)
        self.assertIn({"source": ["role-defer", 0], "destination": ["role-menu", 0]}, lines)

    def test_capture_path_matches_the_working_ableton_midi_monitor(self):
        temporary, output = self.build_device()
        self.addCleanup(temporary.cleanup)
        patcher = json.loads((output / "CL MIDI Console Monitor.maxpat").read_text())["patcher"]
        lines = [item["patchline"] for item in patcher["lines"]]
        boxes = {item["box"]["id"]: item["box"] for item in patcher["boxes"]}
        self.assertEqual(boxes["midi-in"]["outlettype"], ["int"])
        self.assertEqual(boxes["midi-parse"]["outlettype"], ["", "", "", "int", "int", "", "int", ""])
        self.assertIn({"source": ["midi-parse", 3], "destination": ["event-gate", 1]}, lines)
        self.assertFalse(any(item["box"]["id"] == "channel-store" for item in patcher["boxes"]))

    def test_program_names_are_resolved_per_console(self):
        temporary, output = self.build_device()
        self.addCleanup(temporary.cleanup)
        patcher = json.loads((output / "CL MIDI Console Monitor.maxpat").read_text())["patcher"]
        boxes = {item["box"]["id"]: item["box"] for item in patcher["boxes"]}
        lines = [item["patchline"] for item in patcher["lines"]]
        self.assertEqual(boxes["lookup-cl5"]["text"], "js CLMidiConsoleDisplay.js CL5 1")
        self.assertEqual(boxes["lookup-ql1-cc"]["text"], "js CLMidiConsoleDisplay.js QL1_CC 1")
        self.assertEqual(boxes["lookup-ql1-pgm"]["text"], "js CLMidiConsoleDisplay.js QL1_PGM 1")
        self.assertIn({"source": ["event-gate", 0], "destination": ["lookup-cl5", 0]}, lines)
        self.assertIn({"source": ["lookup-cl5", 0], "destination": ["send-cl5", 0]}, lines)
        self.assertIn({"source": ["scene-recv", 0], "destination": ["lookup-cl5", 0], "order": 0}, lines)

        self.assertEqual(boxes["scene-udp"]["text"], "udpreceive 9002")
        self.assertEqual(
            boxes["scene-route"]["text"],
            "route /cl/midi-monitor/scene /cl/midi-monitor/reset",
        )
        self.assertNotIn("scene-oscparse", boxes)
        self.assertNotIn("scene-trim", boxes)
        self.assertIn({"source": ["scene-prepend", 0], "destination": ["scene-send", 0]}, lines)
        self.assertIn({"source": ["scene-udp", 0], "destination": ["scene-route", 0]}, lines)

    def test_lookup_cleans_ableton_metadata_and_places_program_last(self):
        source = DISPLAY.read_text()
        self.assertIn(";\\s*BPM\\s*;\\s*KEY", source)
        self.assertIn('[cleanName(displayName), "/", "Scène", program]', source)
        self.assertIn('replace(/[\\"“”«»]/g, "")', source)
        self.assertIn('["Scène", program]', source)
        self.assertNotIn('"PROGRAMME"', source)
        scene_body = source.split("function scene()", 1)[1].split("function reset()", 1)[0]
        self.assertNotIn('outlet(0, "—")', scene_body)
        self.assertNotIn("launchGraceMs", source)
        self.assertIn("programAwaitingSceneContext", source)
        self.assertIn("render(lastProgram)", scene_body)

    def test_manual_clip_uses_its_own_session_row_name(self):
        source = DISPLAY.read_text()
        self.assertIn('"this_device canonical_parent"', source)
        self.assertIn('trackObserver.property = "playing_slot_index"', source)
        self.assertIn('"live_set scenes " + slotIndex', source)
        self.assertIn("playingSlotSceneName || currentSceneName", source)
        self.assertIn("refreshPlayingSlotScene();", source)
        self.assertIn("if (!trackObserver)", source)
        self.assertIn("function bang()", source)
        refresh_body = source.split("function refreshPlayingSlotScene()", 1)[1].split(
            "function playingSlotChanged()", 1
        )[0]
        self.assertIn("slotIndex >= 0", refresh_body)
        self.assertNotIn('playingSlotSceneName = ""', refresh_body)

        temporary, output = self.build_device()
        self.addCleanup(temporary.cleanup)
        patcher = json.loads((output / "CL MIDI Console Monitor.maxpat").read_text())["patcher"]
        lines = [item["patchline"] for item in patcher["lines"]]
        for lookup in ("lookup-cl5", "lookup-ql1-cc", "lookup-ql1-pgm"):
            self.assertIn(
                {"source": ["role-defer", 0], "destination": [lookup, 0]},
                lines,
            )

    def test_ql1_paths_share_the_last_resolved_title(self):
        source = DISPLAY.read_text()
        self.assertIn('new Global("CLMidiConsoleDisplayState")', source)
        self.assertIn('consoleName.indexOf("QL1") === 0 ? "ql1" : "cl5"', source)
        self.assertIn('sharedDisplay[programKey] = program', source)
        self.assertIn('displayName = String(sharedDisplay[nameKey])', source)
        self.assertIn('sharedDisplay[physicalConsole + "Name"] = ""', source)

    def test_ql1_cc_keeps_the_current_song_title_when_memory_changes(self):
        source = DISPLAY.read_text()
        self.assertIn('consoleName === "QL1 CC"', source)
        self.assertIn('(currentSceneName || playingSlotSceneName)', source)
        self.assertIn('(playingSlotSceneName || currentSceneName)', source)


if __name__ == "__main__":
    unittest.main()
