import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools" / "cl_midi_network"


class MidiNetworkToolsTests(unittest.TestCase):
    def test_guardian_uses_bonjour_and_coremidi(self):
        source = (TOOLS / "CLMIDINetworkGuardian.m").read_text()
        self.assertIn("MIDINetworkSession", source)
        self.assertIn("netServiceName", source)
        self.assertIn("addConnection", source)
        self.assertNotIn("osascript", source)

    def test_simulator_echoes_only_program_changes(self):
        source = (TOOLS / "CLYamahaConsoleSimulator.m").read_text()
        self.assertIn("(status & 0xF0) == 0xC0", source)
        self.assertIn("MIDISend", source)
        self.assertIn("program + 1", source)
        self.assertIn("RTP session endpoints unavailable", source)
        self.assertIn("findEndpoint", source)

    def test_build_script_targets_native_tools(self):
        source = (TOOLS / "build.sh").read_text()
        self.assertIn("-framework CoreMIDI", source)
        self.assertIn("-arch arm64 -arch x86_64", source)
        self.assertIn("CLMIDINetworkGuardian", source)
        self.assertIn("CLYamahaConsoleSimulator", source)
        self.assertIn("CLMIDIRoundTripTester", source)

    def test_legacy_reconnect_never_disconnects_an_unknown_session(self):
        source = (TOOLS / "reconnect_legacy_rtp.applescript").read_text()
        self.assertIn('button "Se connecter"', source)
        self.assertIn('button "Se déconnecter"', source)
        self.assertIn("Une autre session RTP est déjà active", source)
        self.assertNotIn('click button "Se déconnecter"', source)


if __name__ == "__main__":
    unittest.main()
