import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools" / "cl_midi_network"


class LogicBridgeTests(unittest.TestCase):
    def test_transport_demo_is_idempotent_and_ordered(self):
        bridge_source = (TOOLS / "CLLogicBridge.m").read_text(encoding="utf-8")
        self.assertIn("<CLCommandReceiver>", (TOOLS / "CLLogicBridge.h").read_text())
        self.assertNotIn("CoreMIDI", bridge_source)
        self.assertNotIn("MIDIPacket", bridge_source)

        with tempfile.TemporaryDirectory() as temporary_directory:
            output_directory = Path(temporary_directory) / "build"
            subprocess.run(
                [str(TOOLS / "build.sh"), str(output_directory)],
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run(
                [str(output_directory / "CLLogicBridge"), "--demo"],
                check=True,
                capture_output=True,
                text=True,
            )

        state_lines = [line for line in result.stdout.splitlines() if line.startswith("STATE ")]
        command_lines = [line for line in result.stdout.splitlines() if line.startswith("LOGIC COMMAND ")]
        self.assertEqual(
            state_lines,
            [
                "STATE Playing",
                "STATE Playing (unchanged)",
                "STATE Stopped",
                "STATE Recording",
                "STATE Paused",
            ],
        )
        self.assertEqual(len(command_lines), 5)
        self.assertIn("ADAPTER INVOCATIONS 4", result.stdout)


if __name__ == "__main__":
    unittest.main()
