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
        self.assertIn("consumeSelfEcho", source)
        self.assertIn("IGNORED_SELF_ECHO", source)
        self.assertIn("selfEchoBudget = 1", source)

    def test_build_script_targets_native_tools(self):
        source = (TOOLS / "build.sh").read_text()
        self.assertIn('${1:-$SCRIPT_DIR/build}', source)
        self.assertIn("-framework CoreMIDI", source)
        self.assertIn("-arch arm64 -arch x86_64", source)
        self.assertEqual(source.count("-mmacosx-version-min=10.15"), 4)
        self.assertIn("CLMIDINetworkGuardian", source)
        self.assertIn("CLYamahaConsoleSimulator", source)
        self.assertIn("CLMIDIRoundTripTester", source)
        self.assertIn("CLMIDINetworkDashboard", source)

    def test_dashboard_exposes_visible_rtp_status_and_real_round_trip(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text()
        self.assertIn('title:@"RTP HORS LIGNE"', source)
        self.assertIn('title:@"RTP DISPONIBLE"', source)
        self.assertIn('title:@"RTP VALIDÉ"', source)
        self.assertIn('CLMIDIRoundTripTester', source)
        self.assertIn('@"--endpoint"', source)
        self.assertIn('@"--program"', source)
        self.assertIn('latency_ms=', source)
        self.assertIn('MIDINetworkSession', source)
        self.assertIn('open_rtp_settings.applescript', source)
        self.assertIn('_apple-midi._udp.', source)
        self.assertIn('preferredRtpPeer', source)
        self.assertIn('paradis_latin_logo.jpg', source)
        self.assertIn('accentButton:', source)
        self.assertIn('CL MIDI NETWORK ASSISTANT', source)
        self.assertIn('CL AUDIO · MIDI NETWORK · 2026', source)
        self.assertIn('stylePopup:', source)
        self.assertIn('connect_rtp_peer.applescript', source)
        self.assertIn('executeAndReturnError', source)
        connect_method = source.split('- (void)connectSelectedPeer:', 1)[1].split('- (void)refreshEndpoints', 1)[0]
        self.assertNotIn('/usr/bin/osascript', connect_method)
        self.assertNotIn('dispatch_get_global_queue', connect_method)
        self.assertNotIn('pkill', source)

    def test_configurable_reconnect_targets_one_exact_peer(self):
        source = (TOOLS / "connect_rtp_peer.applescript").read_text()
        self.assertIn('peerName', source)
        self.assertIn('__CL_PEER__', source)
        self.assertNotIn('peerName is "__CL_PEER__"', source)
        self.assertIn('Correspondant RTP introuvable', source)
        self.assertIn('Correspondant RTP ambigu', source)
        self.assertIn('click connectButton', source)
        self.assertIn('participantOutline', source)
        self.assertIn('already-connected:', source)
        self.assertIn('checkbox 2 of group 1 of group 4 of toolbar 1', source)
        self.assertIn('networkButtonHelp does not contain "réseau"', source)
        self.assertNotIn('QL1', source)
        self.assertNotIn('click button "Se déconnecter"', source)

    def test_rtp_settings_opener_targets_midi_network_not_avb_browser(self):
        source = (TOOLS / "open_rtp_settings.applescript").read_text()
        self.assertIn('Afficher le studio MIDI', source)
        self.assertIn('checkbox 2 of group 1 of group 4 of toolbar 1', source)
        self.assertIn('help of networkButton', source)
        self.assertIn('click networkButton', source)
        self.assertNotIn('navigateur de périphériques réseau', source.lower())

    def test_peer_listing_excludes_the_local_rtp_session(self):
        source = (TOOLS / "list_rtp_peers.applescript").read_text()
        self.assertIn('Nom de réseau', source)
        self.assertIn('peerName is not localNetworkName', source)
        self.assertIn('"SELF\\t"', source)
        self.assertIn('"PEER\\t"', source)

    def test_legacy_reconnect_never_disconnects_an_unknown_session(self):
        source = (TOOLS / "reconnect_legacy_rtp.applescript").read_text()
        self.assertIn('button "Se connecter"', source)
        self.assertIn('button "Se déconnecter"', source)
        self.assertIn("Une autre session RTP est déjà active", source)
        self.assertNotIn('click button "Se déconnecter"', source)


if __name__ == "__main__":
    unittest.main()
