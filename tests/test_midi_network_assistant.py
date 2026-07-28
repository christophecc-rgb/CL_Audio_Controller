import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "packaging" / "CL_MIDI_Network_Assistant.sh"


class MidiNetworkAssistantLauncherTests(unittest.TestCase):
    def test_selection_uses_an_explicit_applescript_variable(self):
        source = LAUNCHER.read_text(encoding="utf-8")
        self.assertIn("set picked to choose from list", source)
        self.assertIn("return item 1 of picked", source)
        self.assertNotIn("return item 1 of result", source)

    def test_terminal_command_is_passed_as_an_argument(self):
        source = LAUNCHER.read_text(encoding="utf-8")
        self.assertIn("do script (item 1 of argv)", source)
        self.assertNotIn('do script \\"$command', source)

    def test_rtp_reconnection_uses_the_native_guardian(self):
        source = LAUNCHER.read_text(encoding="utf-8")
        self.assertIn('"$TOOLS/CLMIDINetworkGuardian" --peer-name "$peer"', source)
        self.assertIn('--peer-host "$host" --peer-port "$port"', source)
        self.assertNotIn('osascript "$TOOLS/reconnect_legacy_rtp.applescript"', source)


if __name__ == "__main__":
    unittest.main()
