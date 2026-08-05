import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools" / "cl_midi_network"


class MidiMonitorTests(unittest.TestCase):
    def test_monitor_receives_program_change_then_stop_as_commands(self):
        source = (TOOLS / "CLMIDIMonitor.m").read_text(encoding="utf-8")
        self.assertIn('#import "CLMIDIFramework.h"', source)
        self.assertIn("<CLCommandReceiver>", source)
        self.assertIn("receiveCommand:(CLCommand *)command", source)
        self.assertNotIn("MIDIPacket", source)
        self.assertNotIn("CoreMIDI", source)

        with tempfile.TemporaryDirectory() as temporary_directory:
            output_directory = Path(temporary_directory) / "build"
            subprocess.run(
                [str(TOOLS / "build.sh"), str(output_directory)],
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run(
                [str(output_directory / "CLMIDIMonitor"), "--demo"],
                check=True,
                capture_output=True,
                text=True,
            )

        self.assertIn("PROGRAM SELECT", result.stdout)
        self.assertIn("Channel 16", result.stdout)
        self.assertIn("Program 42", result.stdout)
        self.assertIn("STOP", result.stdout)
        self.assertLess(result.stdout.index("PROGRAM SELECT"), result.stdout.index("STOP"))


if __name__ == "__main__":
    unittest.main()
