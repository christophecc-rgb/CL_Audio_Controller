import json
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "create_midi_console_monitor_v2.py"
SOURCE = ROOT / "M4L" / "Devices" / "CL MIDI Console Monitor v2 Configurable"


class MidiConsoleMonitorV2Tests(unittest.TestCase):
    def build(self):
        temporary = tempfile.TemporaryDirectory()
        output = Path(temporary.name)
        subprocess.run(["python3", str(SCRIPT), "--output-dir", str(output)], check=True)
        self.addCleanup(temporary.cleanup)
        return output

    def test_generates_independent_editable_device(self):
        output = self.build()
        maxpat = output / "CL MIDI Console Monitor v2 Configurable.maxpat"
        amxd = output / "CL MIDI Console Monitor v2 Configurable.amxd"
        self.assertTrue(maxpat.exists())
        self.assertTrue(amxd.exists())
        raw = amxd.read_bytes()
        length = struct.unpack("<I", raw[28:32])[0]
        self.assertEqual(json.loads(raw[32:32 + length]), json.loads(maxpat.read_text()))

    def test_has_dynamic_track_and_persistent_console_controls(self):
        patcher = json.loads((self.build() / "CL MIDI Console Monitor v2 Configurable.maxpat").read_text())["patcher"]
        boxes = {item["box"]["id"]: item["box"] for item in patcher["boxes"]}
        self.assertEqual(boxes["source-menu"]["maxclass"], "umenu")
        self.assertEqual(boxes["source-menu"]["varname"], "v2_source_track")
        self.assertEqual(boxes["console-name"]["varname"], "v2_console_name")
        self.assertEqual(boxes["mode-menu"]["items"], ["Commande", "Retour"])
        self.assertEqual(len(boxes["slot-menu"]["items"]), 6)
        self.assertEqual(boxes["autopattr"]["text"], "autopattr")

    def test_live_api_discovers_tracks_and_preserves_track_identity(self):
        source = (SOURCE / "CLMidiConsoleConfigurable.js").read_text()
        self.assertIn('song.getcount("tracks")', source)
        self.assertIn('track.get("name")', source)
        self.assertIn("track.id", source)
        self.assertIn("previousId", source)
        self.assertIn('outlet(0, "append", name)', source)
        self.assertIn("automaticTrackIndex", source)

    def test_old_monitor_is_not_replaced(self):
        self.assertTrue((ROOT / "M4L" / "Devices" / "CL MIDI Console Monitor" / "CL MIDI Console Monitor.amxd").exists())
        self.assertNotEqual(SOURCE.name, "CL MIDI Console Monitor")


if __name__ == "__main__":
    unittest.main()
