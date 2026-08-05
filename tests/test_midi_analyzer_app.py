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
        for title in ("Start Monitoring", "Stop Monitoring", "Clear", "Save Log…"):
            self.assertIn(title, source)
        for column in ("Heure", "Direction", "Source", "Type de commande", "Canal", "Description", "Octets hexadécimaux"):
            self.assertIn(column, source)
        for forbidden in ("MIDIGet", "MIDIPacketList", "MIDIPort", "MIDIClient", "packet->", ".bytes"):
            self.assertNotIn(forbidden, source)
            self.assertNotIn(forbidden, model)

    def test_event_observation_precedes_command_interpretation(self):
        core = (TOOLS / "CLMIDICore.m").read_text(encoding="utf-8")
        header = (TOOLS / "CLMIDICore.h").read_text(encoding="utf-8")
        app = (TOOLS / "CLMIDIAnalyzerApp.m").read_text(encoding="utf-8")
        self.assertIn("eventHandler", header)
        self.assertLess(core.index("eventHandler(event)"), core.index("commandsForEvent:event"))
        self.assertIn("initWithCommand:nil", app)
        self.assertIn("recordForEvent:event", app)


if __name__ == "__main__":
    unittest.main()
