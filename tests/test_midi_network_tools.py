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
        self.assertIn("NSRunLoop currentRunLoop", source)

    def test_round_trip_ignores_immediate_coremidi_local_echoes(self):
        source = (TOOLS / "CLMIDIRoundTripTester.m").read_text()
        self.assertIn("minimumReturnLatencyMs = 35.0", source)
        self.assertIn("IGNORED_LOCAL_ECHO", source)
        self.assertIn("ignored_local_echoes=", source)
        self.assertIn("latencyMs < minimumReturnLatencyMs", source)

    def test_simulator_echoes_only_program_changes(self):
        source = (TOOLS / "CLYamahaConsoleSimulator.m").read_text()
        self.assertIn("(status & 0xF0) == 0xC0", source)
        self.assertIn("MIDISend", source)
        self.assertIn("program + 1", source)
        self.assertIn("RTP session endpoints unavailable", source)
        self.assertIn("findEndpoint", source)
        self.assertIn("consumeSelfEcho", source)
        self.assertIn("IGNORED_SELF_ECHO", source)
        self.assertIn("CLSentHistorySize = 64", source)
        self.assertIn("age <= 2.0", source)
        self.assertIn("pendingConfirmations[16][128]", source)
        self.assertIn("CLMaxPendingConfirmations = 32", source)
        self.assertIn("CLMaxReceivedPerSecond = 64", source)
        self.assertIn("ECHO_CIRCUIT_OPEN", source)
        self.assertIn("COALESCED_DUPLICATE", source)
        self.assertIn("SUPPRESSED_PENDING_CONFIRMATION", source)
        self.assertNotIn("selfEchoBudget", source)
        self.assertIn('containsString:@"RTPResponder"', source)
        self.assertIn('containsString:@"RTP Receiver"', source)
        build = (TOOLS / "build.sh").read_text()
        self.assertIn("CLMIDIRTPResponder", build)
        self.assertIn("CLMIDIRTPAgent", build)
        agent = (TOOLS / "CLMIDIRTPAgent.m").read_text()
        self.assertIn("NSHost.currentHost.localizedName", agent)
        self.assertIn('com.claudio.midi-rtp-agent.plist', agent)
        self.assertIn('@"RunAtLoad": @YES', agent)
        self.assertIn('@"KeepAlive": @YES', agent)
        self.assertIn('@"ThrottleInterval": @5', agent)
        self.assertIn('_cl-midi-rtp-control._udp.', agent)
        self.assertIn('[controlService publish]', agent)

    def test_round_trip_tester_sends_and_matches_the_selected_channel(self):
        source = (TOOLS / "CLMIDIRoundTripTester.m").read_text()
        self.assertIn('@"--channel"', source)
        self.assertIn('expectedChannel - 1', source)
        self.assertIn('== expectedChannel', source)
        self.assertIn('SENT channel=%u', source)
        self.assertIn('observation_ms=500', source)
        self.assertIn('matchingReturnCount > 4', source)
        self.assertIn('totalProgramChangeCount > 16', source)
        self.assertIn('totalProgramChangeCount <= 16', source)
        self.assertIn('LOOP_DETECTED', source)
        self.assertLess(source.index('MIDIClientCreate'), source.index('findEndpoint(YES'))
        self.assertIn('COREMIDI_CLIENT_ERROR', source)
        self.assertIn('RTP_ENDPOINTS_NOT_FOUND', source)
        self.assertIn('COREMIDI_SEND_ERROR', source)
        self.assertIn('sent=yes', source)

    def test_build_script_targets_native_tools(self):
        source = (TOOLS / "build.sh").read_text()
        self.assertIn('${1:-$SCRIPT_DIR/build}', source)
        self.assertIn("-framework CoreMIDI", source)
        self.assertIn("-arch arm64 -arch x86_64", source)
        self.assertEqual(source.count("-mmacosx-version-min=10.15"), 8)
        self.assertIn("CLMIDINetworkGuardian", source)
        self.assertIn("CLYamahaConsoleSimulator", source)
        self.assertIn("CLMIDIRoundTripTester", source)
        self.assertIn("CLMIDINetworkDashboard", source)
        self.assertNotIn("CLYamahaSimulatorDashboard", source)
        self.assertIn("CLMIDICoreMIDIAnalyzer", source)

    def test_core_midi_analyzer_routes_packets_through_a_port_delegate(self):
        port_header = (TOOLS / "CLMIDIPort.h").read_text(encoding="utf-8")
        port_source = (TOOLS / "CLMIDIPort.m").read_text(encoding="utf-8")
        core_source = (TOOLS / "CLMIDICore.m").read_text(encoding="utf-8")
        logger_source = (TOOLS / "CLMIDILogger.m").read_text(encoding="utf-8")

        self.assertIn("CLMIDIPortDelegate", port_header)
        self.assertIn("MIDIGetNumberOfSources", port_source)
        self.assertIn("MIDIPortConnectSource", port_source)
        self.assertIn("MIDIPortDisconnectSource", port_source)
        self.assertIn("initWithBytes:packet->data", port_source)
        self.assertIn("didReceivePacket:receivedPacket", port_source)
        self.assertIn("kMIDIMsgObjectAdded", core_source)
        self.assertIn("kMIDIMsgObjectRemoved", core_source)
        self.assertIn("initWithPacket:packet", core_source)
        self.assertIn("[_logger logEvent:event]", core_source)
        self.assertIn('event.program', logger_source)
        self.assertIn("commandsForEvent:event", core_source)
        self.assertIn("[self.commandReceiver receiveCommand:command]", core_source)

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
        self.assertIn('BOUCLE MIDI DÉTECTÉE', source)
        self.assertIn('désactivez Entrée RTP > Piste', source)
        self.assertNotIn('Routages actifs : Aucun · une seule paire RTP', source)
        self.assertIn('SIMULATEUR DE RETOUR CONSOLE', source)
        self.assertIn('@[@"Test local · retour dédié", @"Test distant · RTP"]', source)
        self.assertIn('startIntegratedSimulator:', source)
        self.assertIn('cl-midi-rtp-control', source)
        self.assertIn('launchSimulatorDevice:', source)
        self.assertIn('stopIntegratedSimulator:', source)
        self.assertIn('50022', source)
        self.assertIn('loopDetectedEndpoint', source)
        self.assertIn('MIDINetworkSession', source)
        self.assertIn('open_rtp_settings.applescript', source)
        self.assertIn('_apple-midi._udp.', source)
        self.assertIn('_cl-midi-rtp-control._udp.', source)
        self.assertIn('preferredRtpPeer', source)
        self.assertIn('paradis_latin_logo.jpg', source)
        self.assertIn('accentButton:', source)
        self.assertIn('CL MIDI NETWORK ASSISTANT', source)
        self.assertIn('CL AUDIO · MIDI NETWORK · 2026', source)
        self.assertIn('stylePopup:', source)
        self.assertIn('Connexion système vers', source)
        self.assertIn('executeAndReturnError', source)
        self.assertIn('CL MIDI Network Assistant.log', source)
        self.assertIn('rtp-connect-pending', source)
        self.assertIn('round-trip-result', source)
        self.assertIn('envoi réussi · aucun retour distant reçu', source)
        self.assertIn('@"DIAGNOSTIC DISTANT · VÉRIFIER RTP"', source)
        self.assertIn('@"Vérifier RTP"', source)
        simulator_method = source.split('- (void)createIntegratedSimulatorPanelInView:', 1)[1].split('- (BOOL)applicationShouldTerminateAfterLastWindowClosed:', 1)[0]
        self.assertIn('SIMULATEUR DE RETOUR CONSOLE', simulator_method)
        self.assertIn('Test local · retour dédié', simulator_method)
        self.assertIn('Test distant · RTP', simulator_method)
        self.assertIn('CLYamahaConsoleSimulator', simulator_method)
        self.assertIn('startIntegratedSimulator:', simulator_method)
        self.assertIn('stopIntegratedSimulator:', simulator_method)
        self.assertIn('sendSimulatorMemory:', simulator_method)
        self.assertIn('@"81"', simulator_method)
        self.assertIn('@"78"', simulator_method)
        self.assertNotIn('addChildWindow:', source)
        self.assertNotIn('simulatorWindow', source)
        self.assertIn('sendto(', source)
        self.assertNotIn('tell application', simulator_method)
        connect_method = source.split('- (void)connectSelectedPeer:', 1)[1].split('- (void)refreshEndpoints', 1)[0]
        self.assertIn('connectPeerThroughSystem:peer automatic:NO', connect_method)
        self.assertNotIn('pkill', source)

    def test_generic_round_trip_is_unreachable_and_hidden_in_local_mode(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        run_test = source.split('- (void)runTest:', 1)[1].split('- (void)openMidiSetup:', 1)[0]
        mode_changed = source.split('- (void)simulatorModeChanged:', 1)[1].split('- (NSTask *)launchSimulatorDevice:', 1)[0]
        refresh = source.split('- (void)refreshEndpoints', 1)[1].split('- (NSString *)toolPath:', 1)[0]

        self.assertIn('if (self.localReturnMode)', run_test)
        self.assertLess(run_test.index('if (self.localReturnMode)'), run_test.index('CLMIDIRoundTripTester'))
        self.assertIn('[self updateRoundTripPanelForCurrentMode]', mode_changed)
        self.assertIn('[self updateRoundTripPanelForCurrentMode]', refresh)
        self.assertIn('@"RETOUR LOCAL DÉDIÉ"', refresh)
        local_branch = refresh.split('if (self.localReturnMode)', 1)[1].split('} else if', 1)[0]
        self.assertNotIn('retour distant', local_branch)
        self.assertIn('CLLocalReturnEndpointName', refresh)
        self.assertIn('CLRTPReturnEndpointName', mode_changed)

    def test_round_trip_panel_tracks_simulator_mode_immediately(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        updater = source.split('- (void)updateRoundTripPanelForCurrentMode {', 1)[1].split('\n}\n', 1)[0]
        setup = source.split('- (void)setupPassiveReturnMonitor', 1)[1].split('- (void)selectPassiveExpectedSourceNamed:', 1)[0]
        presentation = source.split('- (void)applyPresentationMode', 1)[1].split('- (void)updateRoundTripPanelForCurrentMode', 1)[0]
        mode_changed = source.split('- (void)simulatorModeChanged:', 1)[1].split('- (NSTask *)launchSimulatorDevice:', 1)[0]

        self.assertIn('self.localReturnMode = self.returnModeMenu.indexOfSelectedItem == 1', setup)
        self.assertIn('[self updateRoundTripPanelForCurrentMode]', setup)
        self.assertIn('self.localReturnMode = mode == 0', mode_changed)
        self.assertIn('[self updateRoundTripPanelForCurrentMode]', mode_changed)
        self.assertIn('self.testPanel.hidden = !rtpMode', updater)
        self.assertIn('self.testButton.enabled = rtpMode', updater)
        self.assertNotIn('self.testPanel.hidden = NO', presentation)
        self.assertIn('[self updateRoundTripPanelForCurrentMode]', presentation)

        local_state = updater.split('} else {', 1)[1]
        self.assertIn('Validation locale passive · expected / returned', local_state)
        self.assertNotIn('retour distant', local_state)
        self.assertNotIn('System Events', local_state)
        self.assertIn('DIAGNOSTIC DISTANT · VÉRIFIER RTP', updater)
        self.assertIn('Vérifier RTP', updater)

    def test_rtp_settings_script_finds_the_network_globe_by_accessibility_text(self):
        source = (TOOLS / "open_rtp_settings.applescript").read_text()
        self.assertIn("entire contents of toolbar 1", source)
        self.assertIn("Bouton globe Réseau MIDI introuvable", source)
        self.assertIn('perform action "AXPress"', source)
        self.assertIn("checkbox 2 of group 1 of group 4", source)

    def test_dashboard_is_a_network_only_technical_panel(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text()
        self.assertIn('@"DIAGNOSTIC RÉSEAU MIDI"', source)
        self.assertIn('@"SESSION RTP OBSERVÉE"', source)
        self.assertIn('@"PORTS COREMIDI"', source)
        self.assertIn('@"CORRESPONDANTS BONJOUR"', source)
        self.assertNotIn('toggleNetworkSession:', source)
        self.assertNotIn('changeConnectionPolicy:', source)
        self.assertNotIn('session.networkPort', source)
        self.assertIn('session.connections.count', source)
        self.assertIn('Indication API macOS', source)
        self.assertIn('Connexion confirmée par aller-retour MIDI', source)
        self.assertIn('EndpointNames(YES)', source)
        self.assertIn('EndpointNames(NO)', source)
        self.assertIn('MIDIInputPortCreate', source)
        self.assertIn('CLPassiveReturnRead', source)
        self.assertIn('queueReturnedProgram:', source)
        self.assertIn('/private/tmp/CL_MIDI_Console_State.json', source)
        self.assertIn('@"program": self.lastCL5Program >= 0', source)
        self.assertIn('@"program": self.lastQL1Program >= 0', source)
        self.assertIn('@"midi_program": self.lastCL5Program >= 0', source)
        self.assertIn('@"midi_program": self.lastQL1Program >= 0', source)
        self.assertIn('@"scene": self.lastCL5Program >= 0', source)
        self.assertIn('@"scene": self.lastQL1Program >= 0', source)
        self.assertIn('@"midi_program": requestedSceneIsValid', source)
        self.assertIn('@"scene": requestedSceneIsValid', source)
        self.assertIn('cl5[@"midi_program"] != nil', source)
        self.assertIn('ql1[@"midi_program"] != nil', source)
        self.assertIn('@"scene-title-sync"', source)
        self.assertIn('@"lookup-stale"', source)
        self.assertIn('/console-scene-title?console=%@&midi_program=%ld', source)
        self.assertIn('payload[@"title"]', source)
        self.assertIn('returnedMIDIProgram == midiProgram', source)
        self.assertNotIn('payload[@"scenes"]', source)
        self.assertNotIn('payload[@"midi_scenes"]', source)
        self.assertNotIn('midiProgram + 2', source)
        self.assertIn('currentProgram != midiProgram', source)
        self.assertIn('@"received_at": self.lastCL5ProgramAt', source)
        self.assertIn('@"received_at": self.lastQL1ProgramAt', source)
        self.assertIn('@"lastCL5Program"', source)
        self.assertIn('@"lastQL1Program"', source)
        self.assertIn('CLMidiAgeDescription', source)
        self.assertIn('@"En attente du premier retour MIDI"', source)
        self.assertIn('@"✓ Confirmée"', source)
        self.assertIn('✕ Mauvaise scène', source)
        self.assertIn('@"Dernière scène reçue %@"', source)
        return_cards = source.split('- (void)updateConsoleReturnCards {', 1)[1].split('- (void)refreshAbletonSceneTitle {', 1)[0]
        self.assertNotIn('local_fallback', return_cards)
        self.assertNotIn('non confirmée', return_cards)
        self.assertIn('expected[@"validation_status"]', return_cards)
        self.assertNotIn('receivedScene == expectedProgram', return_cards)
        self.assertIn('age > 12.0', return_cards)
        self.assertIn('@"expected_program"', source)
        self.assertNotIn('pendingCL5Program', source)
        self.assertNotIn('pendingQL1Program', source)
        self.assertNotIn('60 * NSEC_PER_MSEC', source)
        self.assertIn('@"title": self.lastCL5Title', source)
        self.assertIn('@"title": self.lastQL1Title', source)
        self.assertNotIn('MIDISend(', source)
        self.assertIn('CL5 · Scène attendue n°—', source)
        self.assertIn('QL1 · Scène attendue n°—', source)
        self.assertIn('updateConsoleReturnCards', source)
        self.assertIn('assistantReturnPanel.hidden = detailed', source)
        self.assertIn('Titre Ableton en attente', source)
        self.assertIn('http://127.0.0.1:5050/status', source)
        self.assertIn('playing_scene_name', source)
        self.assertIn('colorWithRed:0.070 green:0.086 blue:0.110', source)
        self.assertIn('CL_MIDI_Console_State.json', source)
        self.assertIn('--background-monitor', source)
        self.assertNotIn('ltc_timecode', source)
        self.assertIn('@"Diagnostic détaillé"', source)
        self.assertIn('@"Vue Assistant"', source)
        self.assertIn('setContentSize:NSMakeSize(500, 850)', source)
        self.assertIn('setContentSize:NSMakeSize(500, 1100)', source)
        self.assertIn('self.technicalPanel.hidden = !detailed', source)
        self.assertIn('RÉSEAUX CONSOLES', source)
        self.assertIn('self.lastCL5Test', source)
        self.assertIn('self.lastQL1Test', source)
        self.assertNotIn('MIDINetworkSession.defaultSession.enabled = YES', source)
        self.assertNotIn('Activer la session', source)
        self.assertNotIn('Accès : aucun', source)
        self.assertNotIn('toggleNetworkSession:', source)
        self.assertNotIn('changeConnectionPolicy:', source)
        self.assertIn('Activation et autorisations gérées dans Réglages de réseau MIDI macOS', source)
        self.assertIn('Réglages : gérés par macOS', source)
        self.assertIn('Connexion à confirmer par test MIDI', source)
        self.assertIn('ensureGuardianRunning', source)
        self.assertIn('@"CLMIDINetworkGuardian"', source)
        self.assertIn('@[@"--peer-name", peer]', source)
        self.assertIn('[arguments addObjectsFromArray:@[@"--interval", @"2"]]', source)
        self.assertIn('if (self.guardianTask.running) [self.guardianTask terminate]', source)
        self.assertIn('method=SystemMIDI double-click', source)
        self.assertIn('rtp-connect-retry-scheduled', source)
        self.assertIn('retry <= 8', source)
        self.assertNotIn('ensureLegacyWakeIfNeeded', source)
        self.assertNotIn('legacy-wake-retry', source)
        self.assertIn('applicationShouldHandleReopen:', source)
        self.assertIn('[self.window makeKeyAndOrderFront:nil]', source)

    def test_integrated_simulator_manages_persistent_dynamic_devices(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text()
        simulator = source.split('- (NSArray<NSString *> *)allMidiEndpointNames', 1)[1]

        # Defaults and backward-compatible channel mapping.
        self.assertIn('simulatorDeviceWithID:@"cl5" name:@"CL5" channel:1', simulator)
        self.assertIn('simulatorDeviceWithID:@"ql1" name:@"QL1" channel:2', simulator)
        self.assertIn('name = @"CL5"; channel = 1', simulator)
        self.assertIn('name = @"QL1"; channel = 2', simulator)

        # Create, rename/channel edit, delete, and persistence across launches.
        self.assertIn('addSimulatorDevice:', simulator)
        self.assertIn('editSimulatorDevice:', simulator)
        self.assertIn('device[@"name"] = cleanName', simulator)
        self.assertIn('device[@"channel"] = @(midiChannel)', simulator)
        self.assertIn('deleteSimulatorDevice:', simulator)
        self.assertIn('CLSimulatorDevicesDefaultsKey', simulator)
        self.assertIn('arrayForKey:CLSimulatorDevicesDefaultsKey', simulator)
        self.assertIn('setObject:saved forKey:CLSimulatorDevicesDefaultsKey', simulator)

        # Independent/global activation use one dynamic task collection.
        self.assertIn('NSMutableDictionary<NSString *, NSTask *> *simulatorTasks', source)
        self.assertIn('toggleSimulatorDeviceEnabled:', simulator)
        self.assertIn('toggleSimulatorDeviceRunning:', simulator)
        self.assertIn('stopSimulatorDeviceID:', simulator)
        self.assertIn('for (NSMutableDictionary *device in self.simulatorDevices)', simulator)
        self.assertIn('[self.simulatorTasks removeAllObjects]', simulator)
        self.assertNotIn('simulatorCL5Task', source)
        self.assertNotIn('simulatorQL1Task', source)

        # Collision warning, custom return isolation, and safety UI.
        self.assertIn('channelCollisionForChannel:', simulator)
        self.assertIn('@"⚠ Canal déjà utilisé par %@"', simulator)
        self.assertIn('! [device[@"built_in"] boolValue]'.replace('! ', '!'), simulator)
        self.assertIn('recordSimulatorProgram:', source)
        self.assertIn('@"last_program"', simulator)
        self.assertIn('@"last_event_at"', simulator)
        self.assertIn('@"ARRÊTER TOUT"', simulator)
        self.assertIn('@"Simulation active · %lu device%@"', simulator)
        self.assertIn('@"Simulation désactivée · mode spectacle sûr"', simulator)
        self.assertIn('@"PGM %ld · %@ · %@"', simulator)
        self.assertIn('simulatorSceneTitleForProgram:', simulator)
        self.assertIn('clock.dateFormat = @"HH:mm:ss"', simulator)
        self.assertIn('@"Titre non résolu"', simulator)
        self.assertIn('@"event_history"', simulator)
        self.assertIn('while (history.count > 10)', simulator)
        self.assertIn('NSPipe *output = [NSPipe pipe]', simulator)
        self.assertIn('[line hasPrefix:@"RECEIVED "]', simulator)
        self.assertIn('recordSimulatorProgram:midiProgram deviceID:deviceID', simulator)

        # Existing IAC/RTP executable contract remains common to every device.
        self.assertIn('@"CLYamahaConsoleSimulator"', simulator)
        self.assertIn('@"--label", device[@"name"]', simulator)
        self.assertIn('@"--channel", [device[@"channel"] stringValue]', simulator)
        self.assertIn('@"--transport", transport', simulator)

    def test_dashboard_adopts_the_real_discovered_machine_name(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text()
        self.assertIn("selected = names.firstObject", source)
        self.assertIn('removeObjectForKey:@"preferredRtpPeer"', source)
        self.assertIn("NSHost.currentHost.localizedName", source)
        self.assertIn("[available removeObject:computerName]", source)
        self.assertNotIn("if (selected.length && ![available containsObject:selected]) [available addObject:selected]", source)
        self.assertIn("CL5 and QL1 remain MIDI channel labels", source)

    def test_dashboard_buttons_keep_distinct_actions(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text()
        refresh = source.split('- (void)refreshNow:', 1)[1].split('- (void)endpointChanged:', 1)[0]
        settings = source.split('- (void)openMidiSetup:', 1)[1].split('- (NSDictionary *)sendSimulatorAction:', 1)[0]
        connect = source.split('- (void)connectSelectedPeer:', 1)[1].split('- (void)refreshEndpoints', 1)[0]
        timer = source.split('- (void)refreshTimer:', 1)[1].split('- (void)refreshNow:', 1)[0]
        self.assertIn('diagnostic-refresh', refresh)
        self.assertNotIn('ensureLegacyWakeIfNeeded', refresh)
        self.assertNotIn('open_rtp_settings.applescript', refresh)
        self.assertNotIn('ensureLegacyWakeIfNeeded', timer)
        self.assertIn('open_rtp_settings.applescript', settings)
        self.assertIn('midi-settings-open', settings)
        self.assertIn('connectPeerThroughSystem:peer automatic:NO', connect)

    def test_dashboard_separates_console_return_from_local_fallback(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text()
        self.assertIn('@[@"RTP distant", @"Test local dédié"]', source)
        self.assertIn('@"rtp_remote"', source)
        self.assertIn('@"local_dedicated"', source)

    def test_remote_console_menu_excludes_internal_midi_endpoints(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        predicate = source.split('static BOOL CLIsRTPReturnEndpointName', 1)[1].split('\n}', 1)[0]
        refresh = source.split('- (void)refreshEndpoints', 1)[1].split('- (NSString *)toolPath:', 1)[0]
        self.assertIn('[name isEqualToString:CLExpectedEndpointName]', predicate)
        self.assertIn('[name isEqualToString:CLLocalReturnEndpointName]', predicate)
        self.assertEqual(refresh.count('CLIsRTPReturnEndpointName(name)'), 2)
        self.assertIn('CLRTPReturnEndpointName = @"Réseau RTP MB Chris"', source)

    def test_return_mode_selects_fixed_sources_and_guards_rtp_diagnostics(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        changed = source.split('- (void)returnModeChanged:', 1)[1].split('- (void)targetChanged:', 1)[0]
        run_test = source.split('- (void)runTest:', 1)[1].split('- (void)openMidiSetup:', 1)[0]
        selector = source.split('- (void)selectPassiveReturnSourceNamed:', 1)[1].split('- (void)updateCompactSummary', 1)[0]
        self.assertIn('self.localReturnMode = self.returnModeMenu.indexOfSelectedItem == 1', changed)
        self.assertIn('self.returnMonitorStatus = self.localReturnDestination ? noErr', changed)
        self.assertIn('[self selectPassiveReturnSourceNamed:CLRTPReturnEndpointName]', changed)
        self.assertIn('if (self.localReturnMode)', run_test)
        self.assertIn('[name isEqualToString:CLExpectedEndpointName]', selector)
        self.assertIn('[name isEqualToString:CLLocalReturnEndpointName]', selector)

    def test_dashboard_simulator_never_uses_ableton_title_as_return_title(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        method = source.split("- (NSString *)simulatorSceneTitleForProgram:", 1)[1].split("\n}\n", 1)[0]
        self.assertIn('@"returned_midi_program"', method)
        self.assertIn('@"returned_title"', method)
        self.assertIn('@"Titre non résolu"', method)
        self.assertNotIn('@"expected_title"', method)
        self.assertNotIn("currentAbletonSceneTitle", method)

    def test_dashboard_passive_lookup_reads_returned_title_only(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        method = source.rsplit("- (void)resolveSceneTitleForMIDIProgram:", 1)[1].split("\n}\n", 1)[0]
        self.assertIn('/console-scene-title?console=%@&midi_program=%ld', method)
        self.assertIn('payload[@"title"]', method)
        self.assertIn('NSInteger lookupIndex = midiProgram + 1', method)
        self.assertIn('? self.cl5SceneTitleLookupGeneration', method)
        self.assertIn('currentGeneration != lookupGeneration', method)
        self.assertIn(') ? payload[@"title"] : @""', method)
        self.assertNotIn('/status', method)
        self.assertNotIn('localFallback ? @""', source)
        self.assertNotIn('returnModeMenu.indexOfSelectedItem == 1 ? @"" : endpoint', source)
        self.assertIn(
            '[self selectPassiveReturnSourceNamed:CLRTPReturnEndpointName]',
            source,
        )
        endpoint_changed = source.split('- (void)endpointChanged:', 1)[1].split('- (void)returnModeChanged:', 1)[0]
        self.assertNotIn('[self selectPassiveReturnSourceNamed:endpoint]', endpoint_changed)
        self.assertIn('@"return_source": endpoint', source)
        self.assertIn('@"monitor_source": self.localReturnMode ? CLLocalReturnEndpointName', source)
        self.assertIn('@"monitor_status": @(self.returnMonitorStatus)', source)

    def test_returned_program_immediately_starts_canonical_title_lookup(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        returned = source.rsplit('- (void)queueReturnedProgram:', 1)[1].split(
            '- (void)queueExpectedProgram:', 1
        )[0]
        self.assertIn('[self writeConsoleReturnState]', returned)
        self.assertIn('[self resolveSceneTitleForMIDIProgram:program channel:channel]', returned)
        self.assertLess(
            returned.index('[self writeConsoleReturnState]'),
            returned.index('[self resolveSceneTitleForMIDIProgram:program channel:channel]'),
        )
        self.assertNotIn('/status', returned)
        self.assertNotIn('currentAbletonSceneTitle', returned)

    def test_dashboard_has_independent_expected_and_return_coremidi_inputs(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        self.assertIn('CLExpectedEndpointName = @"Gestionnaire IAC Bus 1"', source)
        self.assertIn('CLLocalReturnEndpointName = @"CL MIDI Return Test"', source)
        self.assertIn('CLRTPReturnEndpointName = @"Réseau RTP MB Chris"', source)
        self.assertIn('MIDIDestinationCreate', source)
        self.assertIn('CLPassiveExpectedRead', source)
        self.assertIn('CLPassiveReturnRead', source)
        self.assertIn('expectedMonitorInputPort', source)
        self.assertIn('returnMonitorInputPort', source)
        self.assertIn('queueExpectedProgram:', source)
        self.assertIn('queueReturnedProgram:', source)
        self.assertIn('@"expected_monitor_source"', source)
        self.assertIn('@"return_monitor_source"', source)
        expected = source.rsplit('- (void)queueExpectedProgram:', 1)[1].split('- (void)updateCompactSummary', 1)[0]
        returned = source.rsplit('- (void)queueReturnedProgram:', 1)[1].split('- (void)queueExpectedProgram:', 1)[0]
        self.assertNotIn('lastCL5Program = program', expected)
        self.assertNotIn('lastQL1Program = program', expected)
        self.assertNotIn('expectedCL5Program = program', returned)
        self.assertNotIn('expectedQL1Program = program', returned)
        refresh = source.split('- (void)refreshEndpoints', 1)[1].split('- (NSString *)toolPath:', 1)[0]
        self.assertIn('selectPassiveExpectedSourceNamed:CLExpectedEndpointName', refresh)
        self.assertIn('selectPassiveReturnSourceNamed:CLRTPReturnEndpointName', refresh)

    def test_iac_simulator_is_explicitly_refused_to_protect_expected_role(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        self.assertIn('Gestionnaire IAC Bus 1 est exclusivement la source expected', source)
        self.assertIn('@"--input-endpoint", CLExpectedEndpointName', source)

    def test_local_and_rtp_return_transports_keep_expected_monitor_independent(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        refresh = source.split('- (void)refreshEndpoints', 1)[1].split('- (NSString *)toolPath:', 1)[0]
        mode = source.split('- (void)simulatorModeChanged:', 1)[1].split('- (NSTask *)launchSimulatorDevice:', 1)[0]
        transport = source.split('- (BOOL)simulatorTransport:', 1)[1].split('- (void)startSimulatorDevice:', 1)[0]
        self.assertIn('selectPassiveExpectedSourceNamed:CLExpectedEndpointName', refresh)
        self.assertIn('if (!self.localReturnMode) [self selectPassiveReturnSourceNamed:CLRTPReturnEndpointName]', refresh)
        self.assertNotIn('expectedMonitorSource = 0', mode)
        self.assertNotIn('expectedCL5Program = -1', mode)
        self.assertNotIn('expectedQL1Program = -1', mode)
        self.assertIn('mode == 0 ? CLLocalReturnEndpointName : CLRTPReturnEndpointName', transport)
        self.assertIn('mode == 0 ? @"iac" : @"rtp"', transport)

    def test_dashboard_never_falls_back_to_ableton_for_expected_console_title(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        method = source.rsplit("- (void)updateConsoleReturnCards", 1)[1].split(
            "- (void)refreshAbletonSceneTitle", 1
        )[0]
        self.assertIn('expected[@"expected_title"]', method)
        self.assertIn('@"Titre non résolu"', method)
        self.assertNotIn("currentAbletonSceneTitle", method)

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
        self.assertIn('CLYamahaSimulatorConfigVersion', source)
        self.assertIn('selectItemWithTitle:index == 1 ? @"2" : @"1"', source)
        self.assertIn('[canonicalName containsString:@"QL1"]', source)
        self.assertIn('saveConfiguration', source)

    def test_network_monitor_registers_dynamic_bonjour_startup(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text()
        self.assertIn('com.claudio.midi-network-monitor.plist', source)
        self.assertIn('@"--background-monitor"', source)
        self.assertIn('@"RunAtLoad": @YES', source)
        self.assertIn('@"KeepAlive": @YES', source)
        self.assertIn('refreshTargetMenu', source)
        self.assertIn('preferredRtpPeer', source)
        self.assertIn('ownsPassiveReturnMonitor', source)
        self.assertIn('rtpPeerHosts', source)
        self.assertIn('rtpPeerPorts', source)
        self.assertIn('@"--peer-host"', source)
        self.assertIn('@"--peer-port"', source)
        self.assertIn('getnameinfo', source)
        self.assertIn('NI_NUMERICHOST', source)

    def test_configurable_reconnect_targets_one_exact_peer(self):
        source = (TOOLS / "connect_rtp_peer.applescript").read_text()
        self.assertIn('peerName', source)
        self.assertIn('__CL_PEER__', source)
        self.assertNotIn('peerName is "__CL_PEER__"', source)
        self.assertIn('Correspondant RTP introuvable', source)
        self.assertIn('Correspondant RTP ambigu', source)
        self.assertIn('click connectButton', source)
        self.assertGreaterEqual(source.count('click at clickPoint'), 2)
        self.assertIn('CL_CLICK:', source)
        self.assertIn('repeat 10 times', source)
        self.assertIn('participantOutline', source)
        self.assertIn('already-connected:', source)
        self.assertIn('checkbox 2 of group 1 of group 4 of toolbar 1', source)
        self.assertIn('networkButtonHelp does not contain "réseau"', source)
        self.assertNotIn('QL1', source)
        self.assertNotIn('click button "Se déconnecter"', source)

    def test_rtp_settings_opener_targets_midi_network_not_avb_browser(self):
        source = (TOOLS / "open_rtp_settings.applescript").read_text()
        self.assertIn('Afficher le studio MIDI', source)
        self.assertIn('entire contents of toolbar 1', source)
        self.assertIn('help of candidateElement', source)
        self.assertIn('click networkButton', source)
        self.assertIn('perform action "AXPress" of networkButton', source)
        self.assertIn('static text "Sessions et répertoires"', source)
        self.assertNotIn('navigateur de périphériques réseau', source.lower())

    def test_peer_listing_excludes_the_local_rtp_session(self):
        source = (TOOLS / "list_rtp_peers.applescript").read_text()
        self.assertIn('Nom de réseau', source)
        self.assertIn('peerName is not localNetworkName', source)
        self.assertIn('"SELF\\t"', source)
        self.assertIn('"PEER\\t"', source)

    def test_legacy_reconnect_never_disconnects_an_unknown_session(self):
        source = (TOOLS / "reconnect_legacy_rtp.applescript").read_text()
        self.assertIn('set participantOutline to outline 1', source)
        self.assertIn('set connectButton to button 1 of directoryGroup', source)
        self.assertIn('return "already-connected:" & connectedName', source)
        self.assertIn('bundle identifier is "com.apple.audio.AudioMIDISetup"', source)
        self.assertIn('set visible to false', source)
        self.assertNotIn('click button "Se déconnecter"', source)


if __name__ == "__main__":
    unittest.main()
