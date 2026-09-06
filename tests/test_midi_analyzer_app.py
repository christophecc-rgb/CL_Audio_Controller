import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools" / "cl_midi_network"
NATIVE_TEST = ROOT / "tests" / "native" / "CLMIDIAnalyzerModelTests.m"


class MidiAnalyzerAppTests(unittest.TestCase):
    def test_analyzer_model_preserves_all_abstraction_levels(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            executable = Path(temporary_directory) / "CLMIDIAnalyzerModelTests"
            command = [
                "clang", "-mmacosx-version-min=10.15", "-fobjc-arc", "-fblocks",
                "-Wall", "-Wextra", "-Werror",
                "-framework", "Foundation", "-framework", "CoreMIDI",
                "-I", str(TOOLS),
                str(TOOLS / "CLCommand.m"),
                str(TOOLS / "CLMIDIPacket.m"),
                str(TOOLS / "CLMIDIEvent.m"),
                str(TOOLS / "CLMIDICommandInterpreter.m"),
                str(TOOLS / "CLMIDIAnalyzerModel.m"),
                str(NATIVE_TEST), "-o", str(executable),
            ]
            subprocess.run(command, check=True, capture_output=True, text=True)
            subprocess.run([str(executable)], check=True, capture_output=True, text=True)

    def test_appkit_ui_uses_only_public_framework_objects(self):
        source = (TOOLS / "CLMIDIAnalyzerApp.m").read_text(encoding="utf-8")
        model = (TOOLS / "CLMIDIAnalyzerModel.m").read_text(encoding="utf-8")
        self.assertIn("<AppKit/AppKit.h>", source)
        self.assertIn("CLCommandTraceReceiver", source)
        for title in ("Start Monitoring", "Stop Monitoring", "Clear", "Export CSV…", "Export JSON…", "Compare Capture…"):
            self.assertIn(title, source)
        for column in ("Heure", "Direction", "Source", "Type de commande", "Canal", "Description", "Octets hexadécimaux"):
            self.assertIn(column, source)
        for forbidden in ("MIDIGet", "MIDIPacketList", "MIDIPort", "MIDIClient", "packet->", ".bytes"):
            self.assertNotIn(forbidden, source)
            self.assertNotIn(forbidden, model)

    def test_v2_interface_exposes_filters_exports_and_paradis_latin_branding(self):
        source = (TOOLS / "CLMIDIAnalyzerApp.m").read_text(encoding="utf-8")
        release = (ROOT / "scripts" / "build_release.sh").read_text(encoding="utf-8")
        for control in ("NSSearchField", "typeFilterButton", "channelFilterButton", "sourceFilterField", "resetFilters:"):
            self.assertIn(control, source)
        for binding in ("session.typeFilter", "session.channelFilter", "session.sourceFilter", "session.searchText"):
            self.assertIn(binding, source)
        self.assertIn('@"Tous les canaux"', source)
        for midi_type in ("Control Change", "Program Change", "Note On", "Note Off", "Pitch Bend"):
            self.assertIn(f'@"{midi_type}"', source)
        self.assertIn("channel <= 16", source)
        self.assertIn("boldSystemFontOfSize:17", source)
        self.assertIn('pathForResource:@"paradis_latin_logo" ofType:@"jpg"', source)
        self.assertIn("CL MIDI ANALYZER", source)
        self.assertIn('paradis_latin_logo.jpg', release)
        self.assertIn('local bundled_resource="${7:-}"', release)
        self.assertIn("NSJSONSerialization", source)
        self.assertIn('Capture JSON incompatible', source)

    def test_event_observation_precedes_command_interpretation(self):
        core = (TOOLS / "CLMIDICore.m").read_text(encoding="utf-8")
        header = (TOOLS / "CLMIDICore.h").read_text(encoding="utf-8")
        app = (TOOLS / "CLMIDIAnalyzerApp.m").read_text(encoding="utf-8")
        self.assertIn("eventHandler", header)
        self.assertLess(core.index("eventHandler(event)"), core.index("commandsForEvent:event"))
        self.assertIn("initWithCommand:nil", app)
        self.assertIn("recordForEvent:event", app)
        self.assertIn("eventsForPacket:event.packet", app)
        self.assertIn("[self.session refreshVisibleRecords]", app)
        self.assertIn("sans attendre le", app)

    def test_packet_parser_supports_message_boundaries_and_realtime(self):
        model = (TOOLS / "CLMIDIAnalyzerModel.m").read_text(encoding="utf-8")
        self.assertIn("CLMIDIAnalyzerMessageLength", model)
        self.assertIn("byte >= 0xF8", model)
        self.assertIn("runningStatus", model)


if __name__ == "__main__":
    unittest.main()
