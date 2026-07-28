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

    def test_round_trip_tester_sends_and_matches_the_selected_channel(self):
        source = (TOOLS / "CLMIDIRoundTripTester.m").read_text()
        self.assertIn('@"--channel"', source)
        self.assertIn('expectedChannel - 1', source)
        self.assertIn('== expectedChannel', source)
        self.assertIn('SENT channel=%u', source)

    def test_build_script_targets_native_tools(self):
        source = (TOOLS / "build.sh").read_text()
        self.assertIn('${1:-$SCRIPT_DIR/build}', source)
        self.assertIn("-framework CoreMIDI", source)
        self.assertIn("-arch arm64 -arch x86_64", source)
        self.assertEqual(source.count("-mmacosx-version-min=10.15"), 5)
        self.assertIn("CLMIDINetworkGuardian", source)
        self.assertIn("CLYamahaConsoleSimulator", source)
        self.assertIn("CLMIDIRoundTripTester", source)
        self.assertIn("CLMIDINetworkDashboard", source)
        self.assertIn("CLYamahaSimulatorDashboard", source)

    def test_dashboard_exposes_visible_rtp_status_and_real_round_trip(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text()
        self.assertIn('title:@"RTP HORS LIGNE"', source)
        self.assertIn('title:@"RTP DISPONIBLE"', source)
        self.assertIn('title:@"RTP VALIDÉ"', source)
        self.assertIn('CLMIDIRoundTripTester', source)
        self.assertIn('@"--endpoint"', source)
        self.assertIn('@"--program"', source)
        self.assertIn('@"--channel"', source)
        self.assertIn('@"CL5 · Ch.1"', source)
        self.assertIn('@"QL1 · Ch.2"', source)
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
        simulator_method = source.split('- (void)startSimulator:', 1)[1].split('- (BOOL)applicationShouldTerminateAfterLastWindowClosed:', 1)[0]
        self.assertIn('CLYamahaSimulatorDashboard', simulator_method)
        self.assertIn('isExecutableFileAtPath:', simulator_method)
        self.assertIn('Console Simulator ouvert.', simulator_method)
        self.assertNotIn('tell application', simulator_method)
        connect_method = source.split('- (void)connectSelectedPeer:', 1)[1].split('- (void)refreshEndpoints', 1)[0]
        self.assertNotIn('/usr/bin/osascript', connect_method)
        self.assertNotIn('dispatch_get_global_queue', connect_method)
        self.assertNotIn('pkill', source)

    def test_dashboard_monitors_console_returns_outside_live(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text()
        self.assertIn('MIDIInputPortCreate', source)
        self.assertIn('MIDIPortConnectSource', source)
        self.assertIn('(status & 0xF0) == 0xC0', source)
        self.assertIn('@"RETOUR PROGRAM CHANGE · CANAL 1"', source)
        self.assertIn('@"RETOUR PROGRAM CHANGE · CANAL 2"', source)
        self.assertIn('@"✓ RETOUR REÇU · %@"', source)
        self.assertIn('@"Écoute native CoreMIDI · hors de Live"', source)
        self.assertIn('if (channel == 1)', source)
        self.assertIn('else if (channel == 2)', source)
        self.assertIn('returnUpdateScheduled', source)
        self.assertIn('100 * NSEC_PER_MSEC', source)
        self.assertIn('now - self.lastCL5ProgramAt < 1.0', source)
        self.assertNotIn('dispatch_async(dispatch_get_main_queue(), ^{\n                    [delegate handleProgram:', source)
        self.assertIn('setupSceneContextListener', source)
        self.assertIn('CLSceneContextPort = 9002', source)
        self.assertIn('@"/cl/midi-monitor/scene"', source)
        self.assertIn('self.cl5Scene.stringValue = self.currentSceneName.length', source)
        self.assertIn('@"CL5 · N° %ld"', source)
        self.assertIn('@"QL1 · N° %ld"', source)
        self.assertIn('@"http://127.0.0.1:5050/status"', source)
        self.assertIn('status[@"ltc_timecode"]', source)
        self.assertIn('scheduledTimerWithTimeInterval:0.1', source)
        self.assertIn('@"LTC TIMECODE"', source)
        self.assertIn('self.ltcTimecode.stringValue = display', source)
        self.assertIn('monospacedDigitSystemFontOfSize:18', source)
        self.assertNotIn('self.cl5Timecode', source)
        self.assertNotIn('self.ql1Timecode', source)
        self.assertIn('/private/tmp/CL_MIDI_Console_State.json', source)
        self.assertIn('writePublishedConsoleState', source)

    def test_yamaha_simulator_dashboard_supports_independent_consoles(self):
        source = (TOOLS / "CLYamahaSimulatorDashboard.m").read_text()
        self.assertIn('＋ Ajouter une console', source)
        self.assertIn('CL CONSOLE SIMULATOR', source)
        self.assertIn('Tout démarrer', source)
        self.assertIn('Tout arrêter', source)
        self.assertIn('CL5', source)
        self.assertIn('QL1', source)
        self.assertIn('@"--endpoint"', source)
        self.assertIn('@"--channel"', source)
        self.assertIn('@"--delay-ms"', source)
        self.assertIn('self.rows.count >= 6', source)
        self.assertIn('CLYamahaSimulatorConsoles', source)
        self.assertIn('saveConfiguration', source)

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
