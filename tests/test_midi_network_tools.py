import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools" / "cl_midi_network"


class MidiNetworkToolsTests(unittest.TestCase):
    def test_simulator_tx_is_published_only_as_explicit_return_source(self):
        source = (ROOT / "tools" / "cl_midi_network" / "CLMIDINetworkDashboard.m").read_text()
        self.assertIn('@"source": @"local_simulator_tx"', source)
        self.assertIn('@"local_simulator_tx": self.lastCL5SimulatorTX', source)
        self.assertIn('@"local_simulator_tx": self.lastQL1SimulatorTX', source)
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
        self.assertIn("Endpoint RTP local introuvable", source)
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
        self.assertEqual(source.count("-mmacosx-version-min=10.15"), 9)
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
        self.assertIn('BANC DE TEST MIDI · 16 CANAUX', source)
        self.assertIn('@[@"Ableton local", @"Ableton distant"]', source)
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
        self.assertIn('CL MIDI NETWORK MANAGER', source)
        self.assertIn('CL AUDIO · MIDI NETWORK · 2026', source)
        self.assertIn('stylePopup:', source)
        self.assertIn('Connexion système vers', source)
        self.assertIn('executeAndReturnError', source)
        self.assertIn('CL MIDI Network Assistant.log', source)
        self.assertIn('rtp-connect-pending', source)
        self.assertIn('round-trip-result', source)
        self.assertIn(
            'envoi RTP réussi · aucun simulateur de retour actif sur le Mac distant',
            source
        )
        self.assertIn('@"DIAGNOSTIC DISTANT · VÉRIFIER RTP"', source)
        self.assertIn('@"Vérifier RTP"', source)

        simulator = source.split(
            '- (void)rebuildSimulatorDeviceRows', 1
        )[1].split(
            '- (BOOL)applicationShouldTerminateAfterLastWindowClosed:', 1
        )[0]

        self.assertIn('BANC DE TEST MIDI · 16 CANAUX', simulator)
        self.assertIn('Ableton local', simulator)
        self.assertIn('Ableton distant', simulator)
        self.assertIn('CLYamahaConsoleSimulator', simulator)
        self.assertIn('startIntegratedSimulator:', simulator)
        self.assertIn('stopIntegratedSimulator:', simulator)
        self.assertIn('sendSimulatorMemory:', simulator)

        # Default manual memories remain CL5=81 / QL1=78,
        # but they now belong to dynamic device rows.
        self.assertIn('[deviceID isEqualToString:@"cl5"]', simulator)
        self.assertIn('[deviceID isEqualToString:@"ql1"]', simulator)
        self.assertIn('data1Field.stringValue = @"81"', simulator)
        self.assertIn('data1Field.stringValue = @"78"', simulator)

        self.assertNotIn('addChildWindow:', source)
        self.assertIn('@property NSWindow *simulatorWindow;', source)
        self.assertIn('- (void)openSimulatorWindow:', source)
        self.assertIn('sender == self.devicesWindow || sender == self.simulatorWindow', source)
        self.assertIn('sendto(', source)
        self.assertNotIn('tell application', simulator)

        connect_method = source.split(
            '- (void)connectSelectedPeer:', 1
        )[1].split('- (void)refreshEndpoints', 1)[0]
        self.assertIn(
            'connectPeerThroughSystem:peer automatic:NO',
            connect_method
        )
        self.assertNotIn('pkill', source)

    def test_dashboard_return_monitor_decodes_rtp_running_status_and_timestamps_each_event(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        callback = source.split("static void CLPassiveReturnRead", 1)[1].split(
            "static NSString *CLMidiAgeDescription", 1
        )[0]
        recorder = source.rsplit(
            "- (void)queueReturnedProgram:(UInt8)program channel:(UInt8)channel receivedAt:(NSDate *)receivedAt {", 1
        )[1].split("- (void)queueExpectedProgram:", 1)[0]

        self.assertIn("UInt8 runningStatus = delegate.returnRunningStatus", callback)
        self.assertIn("if (byte >= 0xF8) continue", callback)
        self.assertIn("runningStatus = byte < 0xF0 ? byte : 0", callback)
        self.assertIn("(runningStatus & 0xF0) == 0xC0", callback)
        self.assertIn("receivedAt:NSDate.date", callback)
        self.assertIn("delegate.returnRunningStatus = runningStatus", callback)
        self.assertIn("NSDate *eventAt = receivedAt ?: NSDate.date", recorder)
        self.assertIn("self.lastCL5ProgramAt = eventAt", recorder)
        self.assertIn("self.lastQL1ProgramAt = eventAt", recorder)
        self.assertIn("[self writeConsoleReturnState]", recorder)

    def test_generic_round_trip_is_unreachable_and_hidden_in_local_mode(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        run_test = source.split('- (void)runTest:', 1)[1].split('- (void)openMidiSetup:', 1)[0]
        mode_changed = source.split('- (void)simulatorModeChanged:', 1)[1].split('- (NSTask *)launchSimulatorDevice:', 1)[0]
        refresh = source.split('- (void)refreshEndpoints', 1)[1].split('- (NSString *)toolPath:', 1)[0]

        self.assertIn('CL MIDI Return Test', source)
        self.assertIn('self.returnMonitorSourceName ?: (preferred ?: @"aucune")', source)
        self.assertLess(run_test.index('if (self.localReturnMode)'), run_test.index('CLMIDIRoundTripTester'))
        self.assertIn('[self updateRoundTripPanelForCurrentMode]', mode_changed)
        self.assertIn('[self updateRoundTripPanelForCurrentMode]', refresh)
        self.assertIn('@"RETOUR LOCAL DÉDIÉ"', refresh)
        local_branch = refresh.split('if (self.localReturnMode)', 1)[1].split('} else if', 1)[0]
        self.assertNotIn('retour distant', local_branch)
        self.assertIn('CLLocalReturnEndpointName', refresh)
        self.assertIn('CLPreferredConsoleReturnEndpoint(EndpointNames(YES))', mode_changed)

    def test_round_trip_panel_tracks_simulator_mode_immediately(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        updater = source.split('- (void)updateRoundTripPanelForCurrentMode {', 1)[1].split('\n}\n', 1)[0]
        setup = source.split('- (void)setupPassiveReturnMonitor', 1)[1].split('- (void)selectPassiveExpectedSourceNamed:', 1)[0]
        presentation = source.split('- (void)applyPresentationMode', 1)[1].split('- (void)updateRoundTripPanelForCurrentMode', 1)[0]
        mode_changed = source.split('- (void)simulatorModeChanged:', 1)[1].split('- (NSTask *)launchSimulatorDevice:', 1)[0]

        self.assertIn('self.localReturnMode = self.returnModeMenu.indexOfSelectedItem == 0', setup)
        self.assertIn('[self updateRoundTripPanelForCurrentMode]', setup)
        self.assertNotIn('simulatorModeMenu', source)
        self.assertIn('self.simulatorModeLabel.stringValue = self.localReturnMode ?', mode_changed)
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

    def test_local_assistant_layout_collapses_the_hidden_rtp_test_space(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        layout = source.split('- (void)layoutAssistantViewForRTPMode:(BOOL)rtpMode {', 1)[1].split('\n}', 1)[0]
        self.assertIn('650 + offset', layout)
        self.assertIn('rtpMode ? 104.0 : 0.0', layout)
        self.assertIn('self.assistantReturnPanel.frame = NSMakeRect(16, 90, 468, 215)', layout)
        self.assertIn('self.testPanel.frame = NSMakeRect(16, 343, 468, 96)', layout)
        self.assertIn('self.assistantTestBanner.frame = NSMakeRect(16, 42, 468, 36)', layout)
        self.assertIn('CGFloat modePanelHeight = rtpMode ? 100.0 : 58.0', layout)
        self.assertIn('@"MODE · LOCAL"', layout)

    def test_console_return_cards_keep_cl5_and_ql1_identity_colors(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        cards = source.split('- (void)updateConsoleReturnCards {', 1)[1].split(
            '- (void)refreshAbletonSceneTitle', 1
        )[0]

        # Passe 3 : l'identité visuelle vient désormais du profil du device,
        # et non d'un branchement final codé en dur sur le nom CL5 / QL1.
        self.assertIn('profile[@"palette"]', cards)
        self.assertIn('profile[@"display_name"]', cards)
        self.assertIn('deviceColorFromHex:palette[@"base"]', cards)
        self.assertIn('deviceColorFromHex:palette[@"accent"]', cards)
        self.assertIn('@"productionSupported": @(productionSupported)', cards)
        self.assertIn('console[@"id"] ?: @"device"', cards)
        self.assertNotIn('BOOL isCL5', cards)

    def test_network_manager_return_cards_emphasize_memory_and_resolved_titles(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        setup = source.split('self.cl5ReturnCard =', 1)[1].split('[self createIntegratedSimulatorPanelInView:content]', 1)[0]
        cards = source.split('- (void)updateConsoleReturnCards {', 1)[1].split('- (void)refreshAbletonSceneTitle', 1)[0]
        self.assertIn('@"CL5   PC — → —   …"', setup)
        self.assertIn('@"QL1   PC — → —   …"', setup)
        self.assertNotIn('ReturnTitle', setup)
        self.assertIn('monospacedDigitSystemFontOfSize:28.0', source)
        self.assertIn('titleLabel.stringValue', cards)
        self.assertIn('titleLabel.hidden = !titleLabel.stringValue.length', cards)
        self.assertIn('hasLibrary && resolvedTitle.length', cards)
        self.assertIn('@"Program Change %ld%@%@"', cards)
        self.assertIn('metaLabel.stringValue = @"Control Change"', cards)
        self.assertIn('metaLabel.stringValue = @"Note"', cards)
        self.assertIn('@" · EXP %ld"', cards)
        self.assertIn('confirmed ? @"✓" : mismatch ? @"✕" : stale ? @"!" : @"…"', cards)
        self.assertIn('@"Indéterminé · attendu indisponible"', cards)
        self.assertIn('@"En attente du retour"', cards)
        self.assertIn('@"Retour ancien · %@"', cards)
        self.assertIn('expected[@"expected_title"]', cards)
        self.assertIn('expected[@"returned_title"]', cards)

    def test_console_libraries_are_configured_by_the_network_manager_via_backend(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        self.assertIn('@"BACKEND ET BIBLIOTHÈQUES"', source)
        self.assertIn('status[@"console_scene_library_status"]', source)
        self.assertIn('for (NSDictionary *device in self.deviceProfiles)', source)
        self.assertIn('[signalType isEqualToString:@"program_change"]', source)
        self.assertIn('self.consoleLibraryNameLabels[definition[@"id"]]', source)
        self.assertIn('self.consoleLibraryStateLabels[definition[@"id"]]', source)
        self.assertIn('CGFloat visibleHeight = 76.0', source)
        self.assertIn('self.consoleLibrariesScroll.hasVerticalScroller = definitions.count > 3', source)
        self.assertIn('info[@"entries"]', source)
        self.assertIn('@"✓ %lu mémoires"', source)
        self.assertIn('@"⚠ %@"', source)
        self.assertIn('/console-library/import/%@', source)
        self.assertIn('multipart/form-data; boundary=%@', source)
        self.assertNotIn('parse_import', source)

    def test_ableton_remotes_do_not_expose_console_library_management(self):
        for template_name in ("index.html", "arrangement.html"):
            source = (ROOT / "templates" / template_name).read_text(encoding="utf-8")
            self.assertNotIn('Gérés par CL MIDI Network Manager', source)
            self.assertNotIn('consoleLibrariesStatus', source)
            self.assertNotIn('console_scene_library_status', source)
            self.assertNotIn('id="consoleTitleMode"', source)
            self.assertNotIn('data-library-import=', source)
            self.assertNotIn('data-library-reveal=', source)
            self.assertNotIn('/console-library/import/', source)
            self.assertNotIn("action:'console_title_mode'", source)
            self.assertIn('CLMidiReturnVisual.devicesFromState(state)', source)
            self.assertIn('CLMidiReturnVisual.renderDeviceCards', source)

    def test_integrated_simulator_has_clear_console_rows_and_no_duplicate_details_button(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        rebuild = source.split(
            '- (void)rebuildSimulatorDeviceRows', 1
        )[1].split(
            '- (void)createIntegratedSimulatorPanelInView:', 1
        )[0]
        panel = source.split(
            '- (void)createIntegratedSimulatorPanelInView:', 1
        )[1].split(
            '- (void)sendSimulatorMemory:', 1
        )[0]

        # Device rows are dynamic rather than CL5/QL1 views hard-coded in the panel.
        self.assertIn('for (NSDictionary *device in self.simulatorDevices)', rebuild)
        self.assertIn('NSString *deviceName = device[@"name"]', rebuild)
        self.assertIn('NSInteger channel = [device[@"channel"] integerValue]', rebuild)
        self.assertIn('self.simulatorValueFields[deviceID] = valueFields', rebuild)
        self.assertIn('self.simulatorMemoryFields[deviceID] = data1Field', rebuild)
        self.assertIn('send.identifier = deviceID', rebuild)
        self.assertIn('send.tag = channel', rebuild)
        self.assertIn('toggleSimulatorDeviceRunning:', rebuild)

        # Compact scrollable presentation; delay remains a global simulator setting.
        self.assertIn('self.simulatorDevicesScroll', panel)
        self.assertIn('self.simulatorDeviceRows', panel)
        self.assertIn('@"Délai"', panel)
        self.assertNotIn('addSimulatorDevice:', panel)
        self.assertNotIn('@"Afficher les détails"', panel)
        self.assertNotIn('NSView *cl5Row', panel)
        self.assertNotIn('NSView *ql1Row', panel)

        # The detached test bench gives the 16-channel list a tall vertical scroll.
        self.assertIn('NSMakeRect(16, 16, 728, 668)', panel)
        self.assertIn('NSMakeRect(14, 266, 700, 300)', panel)
        self.assertIn('self.simulatorDevicesScroll.contentSize.height', rebuild)

    def test_simulator_reuses_library_management_and_one_global_stop_action(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        rebuild = source.split('- (void)rebuildSimulatorDeviceRows', 1)[1].split(
            '- (void)openSimulatorWindow:', 1
        )[0]
        panel = source.split('- (void)createIntegratedSimulatorPanelInView:', 1)[1].split(
            '- (void)sendSimulatorMemory:', 1
        )[0]
        stop = source.split('- (void)stopIntegratedSimulator:', 1)[1].split(
            '- (void)toggleSimulatorDeviceEnabled:', 1
        )[0]

        self.assertIn('BOOL hasRelevantLibrary = programChange', rebuild)
        self.assertIn('[protocol isEqualToString:@"midi"] && libraryID.length > 0', rebuild)
        self.assertIn('[self accentButton:@"Bibliothèque…"', rebuild)
        self.assertIn('action:@selector(selectConsoleLibrary:)', rebuild)
        self.assertIn('library.identifier = libraryID', rebuild)
        self.assertNotIn('/console-library/import/', rebuild)

        self.assertIn('[self button:@"■ Tout arrêter"', panel)
        self.assertIn('action:@selector(stopIntegratedSimulator:)', panel)
        self.assertIn('[self.simulatorTasks removeAllObjects]', stop)
        self.assertIn('[self.simulatorOutputBuffers removeAllObjects]', stop)
        self.assertIn('if (task.running) [task terminate]', stop)
        self.assertIn('action:@selector(stopIntegratedSimulator:)', source)
        self.assertIn('self.assistantStopTestsButton = [self accentButton:@"Tout arrêter"', source)

    def test_rtp_settings_script_finds_the_network_globe_by_accessibility_text(self):
        source = (TOOLS / "open_rtp_settings.applescript").read_text()
        self.assertIn("entire contents of toolbar 1", source)
        self.assertIn("Bouton globe Réseau MIDI introuvable", source)
        self.assertIn('perform action "AXPress"', source)
        self.assertIn("checkbox 2 of group 1 of group 4", source)

    def test_dashboard_is_a_network_only_technical_panel(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text()
        self.assertIn('@"INFORMATIONS TECHNIQUES"', source)
        self.assertIn('@"SESSION RTP"', source)
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
        self.assertIn('@"En attente du retour"', source)
        self.assertIn('@"✓ Confirmé par la console"', source)
        self.assertIn('Mismatch · reçu %ld · attendu %ld', source)
        self.assertIn('@"Retour ancien · %@"', source)
        return_cards = source.split('- (void)updateConsoleReturnCards {', 1)[1].split('- (void)refreshAbletonSceneTitle {', 1)[0]
        self.assertIn('local_fallback', return_cards)
        self.assertNotIn('non confirmée', return_cards)
        self.assertIn('expected[@"validation_status"]', return_cards)
        self.assertNotIn('receivedScene == expectedProgram', return_cards)
        self.assertIn('validationStatus isEqualToString:@"stale"', return_cards)
        self.assertIn('@"expected_program"', source)
        self.assertNotIn('pendingCL5Program', source)
        self.assertNotIn('pendingQL1Program', source)
        self.assertNotIn('60 * NSEC_PER_MSEC', source)
        self.assertIn('@"title": self.lastCL5Title', source)
        self.assertIn('@"title": self.lastQL1Title', source)
        manual_send = source.split('- (void)sendSimulatorMemory:', 1)[1].split('- (void)simulatorModeChanged:', 1)[0]
        self.assertIn('MIDISend(self.simulatorMidiOutputPort, destination, &packetList)', manual_send)
        self.assertNotIn('[self toolPath:@"CLMIDIRoundTripTester"]', manual_send)
        self.assertIn('CL5   PC — → —   …', source)
        self.assertIn('QL1   PC — → —   …', source)
        self.assertIn('updateConsoleReturnCards', source)
        self.assertIn('assistantReturnPanel.hidden = detailed', source)
        self.assertNotIn('Titre Ableton en attente', source)
        self.assertIn('http://127.0.0.1:5050/status', source)
        self.assertIn('playing_scene_name', source)
        self.assertIn('[self deviceColorFromHex:palette[@"accent"]', source)
        self.assertIn('for (NSDictionary *device in self.deviceProfiles)', source)
        self.assertIn('CL_MIDI_Console_State.json', source)
        self.assertIn('--background-monitor', source)
        self.assertNotIn('ltc_timecode', source)
        self.assertIn('@"Diagnostic détaillé"', source)
        self.assertIn('@"Vue Spectacle"', source)
        self.assertIn('NSSize targetContentSize = NSMakeSize(500, 650 + offset)', source)
        self.assertIn('setContentSize:NSMakeSize(500, localHeight + offset)', source)
        self.assertIn('CGFloat localHeight = MIN(768.0, MAX(690.0, 650.0 + returnsHeight))', source)
        self.assertIn('self.technicalPanel.hidden = !detailed', source)
        self.assertIn('RÉSEAUX CONSOLES', source)
        self.assertIn('self.lastCL5Test', source)
        self.assertIn('self.lastQL1Test', source)
        self.assertNotIn('MIDINetworkSession.defaultSession.enabled = YES', source)
        self.assertNotIn('Activer la session', source)
        self.assertNotIn('Accès : aucun', source)
        self.assertNotIn('toggleNetworkSession:', source)
        self.assertNotIn('changeConnectionPolicy:', source)
        self.assertNotIn('Activation et autorisations gérées dans Réglages de réseau MIDI macOS', source)
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
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        simulator = source.split(
            "- (NSMutableDictionary *)simulatorDeviceWithID:", 1
        )[1].split(
            "#pragma mark - Device Profiles editor", 1
        )[0]

        # Le simulateur reste dynamique, mais sa source canonique est désormais
        # deviceProfiles plutôt qu'une seconde liste éditable indépendante.
        self.assertIn("CLSimulatorDevicesDefaultsKey", simulator)
        self.assertIn("syncSimulatorDevicesFromProfiles", simulator)
        self.assertIn("simulatorDeviceIDForProfile:", simulator)
        self.assertIn("deviceProfileForSimulatorID:", simulator)
        self.assertIn("self.deviceProfiles", simulator)
        self.assertIn('@"signal_type"', simulator)
        self.assertIn('@"program_change"', simulator)
        self.assertIn('profile[@"rx"][@"enabled"]', simulator)
        self.assertIn('profile[@"enabled"]', simulator)
        self.assertIn('profile[@"protocol"]', simulator)
        self.assertIn('simulableSignalTypes', simulator)
        self.assertIn('@"control_change"', simulator)
        self.assertIn('@"note"', simulator)

        # CL5/QL1 sont conservées via leurs profils historiques et legacy_key,
        # plus par création codée en dur dans le simulateur.
        self.assertIn('@"console_a"', simulator)
        self.assertIn('@"console_b"', simulator)
        self.assertIn('profile[@"legacy_key"]', simulator)
        self.assertNotIn(
            'simulatorDeviceWithID:@"cl5" name:@"CL5" channel:1',
            simulator,
        )
        self.assertNotIn(
            'simulatorDeviceWithID:@"ql1" name:@"QL1" channel:2',
            simulator,
        )

        # Les appareils supprimés/désactivés ne doivent pas laisser tourner
        # un simulateur fantôme.
        self.assertIn("wantedIDs", simulator)
        self.assertIn("[task terminate]", simulator)
        self.assertIn("[self persistSimulatorDevices]", simulator)

        # La palette du simulateur suit maintenant le profil Appareils.
        self.assertIn('profile[@"palette"]', simulator)
        self.assertIn("deviceColorFromHex:", simulator)


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
        self.assertIn('@[@"Ableton local", @"Ableton distant"]', source)
        self.assertIn('@"rtp_remote"', source)
        self.assertIn('@"local_dedicated"', source)
        self.assertIn('@"http://127.0.0.1:5055/network-config"', source)
        self.assertIn('[self synchronizeOperatingMode]', source)

    def test_remote_console_menu_excludes_internal_midi_endpoints(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        predicate = source.split('static BOOL CLIsRTPReturnEndpointName', 1)[1].split('\n}', 1)[0]
        refresh = source.split('- (void)refreshEndpoints', 1)[1].split('- (NSString *)toolPath:', 1)[0]
        self.assertIn('[name isEqualToString:CLExpectedEndpointName]', predicate)
        self.assertIn('[name isEqualToString:CLLocalReturnEndpointName]', predicate)
        self.assertGreaterEqual(refresh.count('CLIsRTPReturnEndpointName(name)'), 2)
        self.assertIn('CLRTPReturnEndpointName = @"Réseau RTP MB Chris"', source)

    def test_return_mode_selects_saved_dynamic_source_and_guards_rtp_diagnostics(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        changed = source.split('- (void)returnModeChanged:', 1)[1].split('- (void)targetChanged:', 1)[0]
        run_test = source.split('- (void)runTest:', 1)[1].split('- (void)openMidiSetup:', 1)[0]
        selector = source.split('- (void)selectPassiveReturnSourceNamed:', 1)[1].split('- (void)updateCompactSummary', 1)[0]
        simulator_changed = source.split('- (void)simulatorModeChanged:', 1)[1].split('- (NSTask *)launchSimulatorDevice:', 1)[0]
        self.assertIn('[self requestOperatingMode:self.returnModeMenu.indexOfSelectedItem == 0 ? @"local" : @"remote"]', changed)
        self.assertIn('self.localReturnMode = local', changed)
        self.assertIn('[self simulatorModeChanged:nil]', changed)
        self.assertIn('self.returnMonitorStatus =', simulator_changed)
        self.assertIn('self.localReturnDestination ? noErr : kMIDIUnknownEndpoint;', simulator_changed)
        self.assertIn('CLPreferredConsoleReturnEndpoint(EndpointNames(YES))', simulator_changed)
        self.assertIn('[self selectPassiveReturnSourceNamed:preferred]', simulator_changed)
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
        self.assertIn('CLConsoleReturnEndpointPreference = @"consoleReturnEndpoint"', source)
        self.assertIn('CLPreferredConsoleReturnEndpoint', source)
        endpoint_changed = source.split('- (void)endpointChanged:', 1)[1].split('- (void)returnModeChanged:', 1)[0]
        self.assertIn('[self selectPassiveReturnSourceNamed:endpoint]', endpoint_changed)
        self.assertIn('setObject:endpoint forKey:CLConsoleReturnEndpointPreference', endpoint_changed)
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
        self.assertIn('selectPassiveReturnSourceNamed:preferred', refresh)

    def test_return_callback_routes_real_program_changes_through_device_profiles(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        parser = source.split('static void CLPassiveReturnRead', 1)[1].split(
            'static void CLIsolatedDeviceTestRead', 1
        )[0]
        routing = source.split('- (void)rebuildReturnDeviceRouting', 1)[1].split(
            '- (void)selectPassiveExpectedSourceNamed:', 1
        )[0]
        returned = source.rsplit('- (void)queueReturnedProgram:', 1)[1].split(
            '- (void)queueExpectedProgram:', 1
        )[0]
        writer = source.split('- (void)writeConsoleReturnState', 1)[1].split(
            '- (NSColor *)deviceColorFromHex:', 1
        )[0]
        self.assertNotIn('channel == 1 || channel == 2', parser)
        self.assertIn('[delegate queueReturnedProgram:byte channel:channel receivedAt:NSDate.date]', parser)
        self.assertIn('device[@"enabled"]', routing)
        self.assertIn('device[@"protocol"]', routing)
        self.assertIn('device[@"signal_type"]', routing)
        self.assertIn('device[@"rx"]', routing)
        self.assertIn('self.returnDeviceIDByChannel[@(channel)]', returned)
        self.assertIn('self.returnedDeviceStates[deviceID]', returned)
        self.assertIn('@"source": @"physical_midi"', returned)
        self.assertIn('if (channel != 1 && channel != 2)', returned)
        self.assertIn('self.lastCL5Program = program', returned)
        self.assertIn('self.lastQL1Program = program', returned)
        self.assertIn('@"returned_devices": self.returnedDeviceStates', writer)

    def test_generic_return_path_does_not_use_test_bench_or_simulator_as_return_truth(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        returned = source.rsplit('- (void)queueReturnedProgram:', 1)[1].split(
            '- (void)queueExpectedProgram:', 1
        )[0]
        bench = source.split('- (void)startIsolatedDeviceTestRX:', 1)[1].split(
            '- (void)windowWillClose:', 1
        )[0]
        self.assertNotIn('deviceTestReceived', returned)
        self.assertNotIn('last_event_at', returned)
        self.assertNotIn('local_simulator_tx', returned)
        self.assertNotIn('returnedDeviceStates', bench)

    def test_expected_parser_handles_running_status_and_packet_boundaries(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        parser = source.split('static void CLPassiveExpectedRead', 1)[1].split(
            'static void CLPassiveReturnRead', 1
        )[0]
        self.assertIn('UInt8 runningStatus = delegate.expectedRunningStatus', parser)
        self.assertIn('if (byte >= 0xF8) continue;', parser)
        self.assertIn('runningStatus = byte < 0xF0 ? byte : 0;', parser)
        self.assertIn('(runningStatus & 0xF0) == 0xC0', parser)
        self.assertNotIn('channel == 1 || channel == 2', parser)
        self.assertIn('[delegate queueExpectedProgram:byte channel:channel]', parser)
        self.assertIn('delegate.expectedRunningStatus = runningStatus', parser)
        self.assertNotIn('queueReturnedProgram:', parser)

    def test_expected_callback_routes_configured_channels_to_generic_device_state(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        routing = source.split('- (void)rebuildReturnDeviceRouting {', 1)[1].split(
            '- (void)selectPassiveExpectedSourceNamed:', 1
        )[0]
        expected = source.rsplit('- (void)queueExpectedProgram:', 1)[1].split(
            '- (void)updateCompactSummary', 1
        )[0]
        writer = source.split('- (void)writeConsoleReturnState', 1)[1].split(
            '- (NSColor *)deviceColorFromHex:', 1
        )[0]
        self.assertIn('self.expectedDeviceIDByChannel = expectedRouting.copy', routing)
        self.assertIn('device[@"enabled"]', routing)
        self.assertIn('device[@"protocol"]', routing)
        self.assertIn('device[@"signal_type"]', routing)
        self.assertIn('device[@"tx"]', routing)
        self.assertIn('self.expectedDeviceIDByChannel[@(channel)]', expected)
        self.assertIn('if (!deviceID.length) return;', expected)
        self.assertIn('self.expectedDeviceStates[deviceID]', expected)
        self.assertIn('@"expected_midi_program": @(program)', expected)
        self.assertIn('@"expected_scene_memory": @(program + 1)', expected)
        self.assertIn('@"expected_activated_at": @([receivedAt timeIntervalSince1970])', expected)
        self.assertIn('@"source": @"ableton_iac_output"', expected)
        self.assertIn('if (channel != 1 && channel != 2)', expected)
        self.assertIn('self.expectedCL5Program = program', expected)
        self.assertIn('self.expectedQL1Program = program', expected)
        self.assertIn('@"expected_devices": self.expectedDeviceStates', writer)

    def test_generic_expected_is_only_written_by_passive_expected_callback_path(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        bench = source.split('- (void)startIsolatedDeviceTestRX:', 1)[1].split(
            '- (void)windowWillClose:', 1
        )[0]
        simulator = source.split('- (void)sendSimulatorMemory:', 1)[1].split(
            '#pragma mark - Device Profiles editor', 1
        )[0]
        self.assertNotIn('expectedDeviceStates', bench)
        self.assertNotIn('expectedDeviceStates', simulator)

    def test_expected_diagnostic_instruments_connection_callback_and_state_only(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        self.assertIn('/private/tmp/CL_MIDI_EXPECTED_DIAGNOSTIC.log', source)
        for event in (
            "EXPECTED_SOURCE_ENUM", "EXPECTED_SOURCE_SELECTED",
            "EXPECTED_INPUT_PORT_CREATED", "EXPECTED_SOURCE_CONNECTED",
            "EXPECTED_CALLBACK_ENTER", "EXPECTED_PACKET",
            "EXPECTED_PROGRAM_DECODED", "EXPECTED_STATE_UPDATED",
        ):
            self.assertIn(f'@"{event}"', source)
        self.assertIn('MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID', source)
        self.assertIn('callback=CLPassiveExpectedRead', source)
        self.assertIn('[sourceName isEqualToString:name]', source)
        self.assertIn('if (self.ownsPassiveReturnMonitor) CLResetExpectedDiagnostic();', source)
        self.assertNotIn('EXPECTED_HEARTBEAT', source)

    def test_iac_simulator_is_explicitly_refused_to_protect_expected_role(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        self.assertIn('Gestionnaire IAC Bus 1 est exclusivement la source expected', source)
        self.assertIn('[CLSimulatorInputEndpointNames() containsObject:CLExpectedEndpointName]', source)
        manual_send = source.split('- (void)sendSimulatorMemory:', 1)[1].split('- (void)simulatorModeChanged:', 1)[0]
        self.assertIn('self.simulatorEndpointMenu.titleOfSelectedItem', manual_send)
        self.assertNotIn('self.localReturnMode ? CLExpectedEndpointName', manual_send)

    def test_local_manual_simulator_sends_directly_to_selected_technical_destination(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        manual_send = source.split('- (void)sendSimulatorMemory:', 1)[1].split(
            '- (void)simulatorModeChanged:', 1
        )[0]

        self.assertNotIn('self.localReturnDestination', manual_send)
        self.assertIn('EndpointNames(NO)', manual_send)
        self.assertIn('MIDIGetNumberOfDestinations()', manual_send)
        self.assertIn('MIDIClientCreate(', manual_send)
        self.assertIn('self.simulatorMidiClient', manual_send)
        self.assertIn('self.simulatorMidiOutputPort', manual_send)
        self.assertIn('MIDIOutputPortCreate(', manual_send)
        self.assertIn('MIDISend(self.simulatorMidiOutputPort, destination, &packetList)', manual_send)
        self.assertNotIn('self.returnMonitorClient', manual_send)
        self.assertNotIn('self.ownsPassiveReturnMonitor', manual_send)
        self.assertNotIn('MIDIPortDispose(outputPort)', manual_send)
        self.assertIn('programChange ? data1Input - 1 : data1Input', manual_send)
        self.assertIn('programChange ? 0xC0', manual_send)
        self.assertIn('((channel - 1) & 0x0F)', manual_send)
        self.assertIn('if (programChange) [self recordSimulatorProgram:data1 channel:channel]', manual_send)
        self.assertIn('sendStatus != noErr', manual_send)
        self.assertNotIn('[self toolPath:@"CLMIDIRoundTripTester"]', manual_send)
        self.assertNotIn('MIDIGetSource', manual_send)
        self.assertNotIn('MIDIPortConnectSource', manual_send)
        self.assertNotIn('queueExpectedProgram', manual_send)
        self.assertNotIn('queueReturnedProgram', manual_send)
        self.assertNotIn('writeConsoleReturnState', manual_send)

        shutdown = source.split('- (NSApplicationTerminateReply)applicationShouldTerminate:', 1)[1].split(
            '\n}', 1
        )[0]
        self.assertIn('MIDIPortDispose(self.simulatorMidiOutputPort)', shutdown)
        self.assertIn('MIDIClientDispose(self.simulatorMidiClient)', shutdown)

    def test_secondary_window_refreshes_canonical_expected_state_from_shared_monitor(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        loader = source.split('- (void)loadPublishedConsoleReturnState', 1)[1].split('- (void)writeConsoleReturnState', 1)[0]
        cards = source.split('- (void)updateConsoleReturnCards {', 1)[1].split('- (void)refreshAbletonSceneTitle', 1)[0]
        self.assertIn('self.expectedCL5State = cl5', loader)
        self.assertIn('self.expectedQL1State = ql1', loader)
        self.assertIn('NSString *expectedDisplay = hasExpectedProgram', cards)
        self.assertIn('NSString *returnedDisplay = hasReturn', cards)

    def test_local_and_rtp_return_transports_keep_expected_monitor_independent(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        refresh = source.split('- (void)refreshEndpoints', 1)[1].split('- (NSString *)toolPath:', 1)[0]
        mode = source.split('- (void)simulatorModeChanged:', 1)[1].split('- (NSTask *)launchSimulatorDevice:', 1)[0]
        transport = source.split('- (BOOL)simulatorTransport:', 1)[1].split('- (void)startSimulatorDevice:', 1)[0]
        self.assertIn('selectPassiveExpectedSourceNamed:CLExpectedEndpointName', refresh)
        self.assertIn('[self selectPassiveReturnSourceNamed:preferred]', refresh)
        self.assertNotIn('if (!self.localReturnMode &&', refresh)
        self.assertNotIn('expectedMonitorSource = 0', mode)
        self.assertNotIn('expectedCL5Program = -1', mode)
        self.assertNotIn('expectedQL1Program = -1', mode)
        self.assertIn('BOOL local = self.localReturnMode', transport)
        self.assertIn('NSString *requiredEndpoint = selectedEndpoint', transport)
        self.assertIn('local ? @"iac" : @"rtp"', transport)
        self.assertIn('EXPECTED absent : Gestionnaire IAC Bus 1 introuvable', transport)
        self.assertNotIn('self.localReturnDestination', transport)
        self.assertIn('Destination MIDI locale indisponible', transport)

    def test_local_simulator_destination_uses_dedicated_return_endpoint(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        snapshot = source.split('- (void)applyEndpointSnapshotWithSources:', 1)[1].split(
            '- (NSString *)toolPath:', 1
        )[0]
        send = source.split('- (void)sendSimulatorMemory:', 1)[1].split(
            '- (void)simulatorModeChanged:', 1
        )[0]
        transport = source.split('- (BOOL)simulatorTransport:', 1)[1].split(
            '- (void)startSimulatorDevice:', 1
        )[0]

        self.assertIn(
            'if ([destinations containsObject:CLLocalReturnEndpointName])',
            snapshot,
        )
        self.assertIn(
            '[localDestinations addObject:CLLocalReturnEndpointName]',
            snapshot,
        )
        self.assertIn(
            '? CLLocalReturnEndpointName',
            snapshot,
        )
        self.assertIn(
            'self.simulatorEndpointMenu.enabled = localDestinations.count > 0',
            snapshot,
        )

        self.assertIn(
            '![endpoint isEqualToString:CLLocalReturnEndpointName]',
            send,
        )
        self.assertIn(
            '![EndpointNames(NO) containsObject:endpoint]',
            send,
        )

        self.assertIn(
            '![requiredEndpoint isEqualToString:CLLocalReturnEndpointName]',
            transport,
        )
        self.assertIn(
            '![EndpointNames(NO) containsObject:requiredEndpoint]',
            transport,
        )

        self.assertNotIn(
            '!CLIsProtectedDeviceTestEndpoint(name)',
            snapshot,
        )

    def test_return_monitor_handles_missing_source_and_has_single_publisher(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        selector = source.split('- (void)selectPassiveReturnSourceNamed:', 1)[1].split(
            '- (void)updateCompactSummary', 1
        )[0]
        writer = source.split('- (void)writeConsoleReturnState', 1)[1].split(
            '- (void)resolveSceneTitleForMIDIProgram:', 1
        )[0]
        setup = source.split('- (void)setupPassiveReturnMonitor', 1)[1].split(
            '- (void)selectPassiveExpectedSourceNamed:', 1
        )[0]
        self.assertNotIn('if (selectedSource == self.returnMonitorSource) return;', selector)
        self.assertIn('if (selectedSource && selectedSource == self.returnMonitorSource)', selector)
        self.assertIn('self.returnMonitorStatus = kMIDIUnknownEndpoint', selector)
        self.assertIn('if (!self.ownsPassiveReturnMonitor) return;', selector)
        self.assertIn('if (!self.ownsPassiveReturnMonitor) return;', writer)
        self.assertIn('if (!self.ownsPassiveReturnMonitor) return;', setup)
        self.assertIn('flock(CLBackgroundMonitorLock, LOCK_EX | LOCK_NB)', source)

    def test_remote_simulator_selects_and_validates_a_local_rtp_endpoint(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        setup = source.split('- (void)createIntegratedSimulatorPanelInView:', 1)[1].split('- (void)sendSimulatorMemory:', 1)[0]
        refresh = source.split('- (void)refreshEndpoints', 1)[1].split('- (NSString *)toolPath:', 1)[0]
        mode = source.split('- (void)simulatorModeChanged:', 1)[1].split('- (NSTask *)launchSimulatorDevice:', 1)[0]
        transport = source.split('- (BOOL)simulatorTransport:', 1)[1].split('- (void)startSimulatorDevice:', 1)[0]
        self.assertIn('@selector(simulatorEndpointChanged:)', setup)
        self.assertIn('NSMutableOrderedSet<NSString *> *localRTPNames', refresh)
        self.assertIn('[destinationSet containsObject:name]', refresh)
        self.assertIn('simulatorLocalRtpEndpoint', source)
        self.assertIn('@"QL1 simulator"', source)
        self.assertIn('self.simulatorEndpointMenu.enabled = localRTPEndpoints.count > 0', refresh)
        self.assertNotIn('[self.simulatorEndpointMenu selectItemWithTitle:CLRTPReturnEndpointName]', mode)
        self.assertIn('[CLLocalRTPEndpointNames() containsObject:requiredEndpoint]', transport)
        self.assertIn('Endpoint RTP local introuvable', transport)
        self.assertNotIn('mode == 0 ? CLLocalReturnEndpointName : CLRTPReturnEndpointName', transport)

    def test_remote_simulator_input_and_output_are_independent(self):
        dashboard = (TOOLS / "CLMIDINetworkDashboard.m").read_text(
            encoding="utf-8"
        )
        engine = (TOOLS / "CLYamahaConsoleSimulator.m").read_text(
            encoding="utf-8"
        )
        launch = dashboard.split(
            '- (NSTask *)launchSimulatorDevice:', 1
        )[1].split(
            '- (BOOL)simulatorTransport:', 1
        )[0]
        manual = dashboard.split(
            '- (void)sendSimulatorMemory:', 1
        )[1].split(
            '- (void)simulatorModeChanged:', 1
        )[0]

        self.assertIn('@"DESTINATION"', dashboard)
        self.assertIn('@"SOURCE AUTO"', dashboard)
        self.assertIn('@"Aucune"', dashboard)
        self.assertIn('CLSimulatorInputEndpointNames()', dashboard)

        self.assertIn(
            'if (input.length && ![input isEqualToString:@"Aucune"])',
            launch
        )
        self.assertIn(
            'addObjectsFromArray:@[@"--input-endpoint", input]',
            launch
        )
        self.assertNotIn(
            '@"--input-endpoint", CLExpectedEndpointName',
            launch
        )

        self.assertIn(
            'argumentValue(arguments, @"--input-endpoint",',
            engine
        )
        self.assertIn(
            'responderMode ? endpointSearchName : @""',
            engine
        )
        self.assertIn('echoEnabled = inputWasConfigured', engine)
        self.assertIn('Source automatique indisponible', engine)
        self.assertIn('Envoi manuel RTP disponible', engine)

        # Manual send remains independent from the responder process.
        self.assertNotIn('startSimulatorDevice:', manual)
        self.assertIn(
            'self.simulatorEndpointMenu.titleOfSelectedItem',
            manual
        )
        self.assertIn('@"--channel"', manual)
        self.assertIn(
            '[self toolPath:@"CLYamahaConsoleSimulator"]',
            manual
        )
        self.assertIn('@"--send-program"', manual)
        self.assertIn('@"--no-echo"', manual)

        # Manual memory is resolved from the selected dynamic device,
        # not from a hard-coded CL5/QL1 pair.
        self.assertIn(
            'self.simulatorValueFields[deviceID]',
            manual
        )
        self.assertIn(
            'device ? [device[@"channel"] integerValue] : sender.tag',
            manual
        )
        self.assertNotIn(
            'channel == 1 ? self.simulatorCL5MemoryField : self.simulatorQL1MemoryField',
            manual
        )

    def test_remote_simulator_compact_layout_keeps_controls_on_separate_rows(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(
            encoding="utf-8"
        )
        setup = source.split(
            '- (void)createIntegratedSimulatorPanelInView:', 1
        )[1].split(
            '- (void)sendSimulatorMemory:', 1
        )[0]
        rebuild = source.split(
            '- (void)rebuildSimulatorDeviceRows', 1
        )[1].split(
            '- (void)createIntegratedSimulatorPanelInView:', 1
        )[0]

        # Mode / destination / source controls remain independent.
        self.assertIn('NSMakeRect(14, 580, 230, 22)', setup)
        self.assertIn('NSMakeRect(250, 578, 180, 24)', setup)
        self.assertIn('NSMakeRect(438, 578, 156, 24)', setup)

        # Device controls now live in compact dynamic rows.
        self.assertIn('self.simulatorDevicesScroll', setup)
        self.assertIn('NSMakeRect(14, 266, 700, 300)', setup)
        self.assertIn(
            '[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 686, 28)]',
            rebuild
        )
        self.assertIn(
            '[[NSTextField alloc] initWithFrame:NSMakeRect(260, 3, 46, 22)]',
            rebuild
        )
        self.assertNotIn('NSMakeRect(258, 86, 196, 28)', setup)

    def test_integrated_simulator_is_signal_aware_and_isolated(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        sync = source.split('- (void)syncSimulatorDevicesFromProfiles', 1)[1].split(
            '- (void)loadSimulatorDevices', 1
        )[0]
        rebuild = source.split('- (void)rebuildSimulatorDeviceRows', 1)[1].split(
            '- (void)createIntegratedSimulatorPanelInView:', 1
        )[0]
        manual = source.split('- (void)sendSimulatorMemory:', 1)[1].split(
            '- (void)simulatorModeChanged:', 1
        )[0]
        auto = source.split('- (void)startSimulatorDevice:', 1)[1].split(
            '- (BOOL)editDevice:', 1
        )[0]

        self.assertIn('[NSSet setWithObjects:@"program_change", @"control_change", @"note", nil]', sync)
        self.assertIn('![protocol isEqualToString:@"midi"]', sync)
        self.assertIn('!profileEnabled || !rxEnabled', sync)
        self.assertNotIn('!programChange', sync)
        for hardcode in ('device_3', 'cc3', 'note4', 'QL3'):
            self.assertNotIn(hardcode, sync + rebuild + manual)

        self.assertIn('@"PC"', rebuild)
        self.assertIn('@"CC"', rebuild)
        self.assertIn('@"Note"', rebuild)
        self.assertIn('@"controller"', rebuild)
        self.assertIn('@"value"', rebuild)
        self.assertIn('@"velocity"', rebuild)
        self.assertIn('constraintEqualToConstant:28', rebuild)
        self.assertIn('NSUInteger deviceCount = visibleDeviceCount', rebuild)
        self.assertIn('(deviceCount * rowHeight)', rebuild)
        self.assertIn('((deviceCount - 1) * rowSpacing)', rebuild)
        self.assertIn('documentHeight > visibleHeight', rebuild)

        self.assertIn('data1Input >= 1 && data1Input <= 128', manual)
        self.assertIn('data1Input >= 0 && data1Input <= 127', manual)
        self.assertIn('data2Input >= 0 && data2Input <= 127', manual)
        self.assertIn('data1Input - 1', manual)
        self.assertIn('0xB0', manual)
        self.assertIn('0x90', manual)
        self.assertIn('packetList.packet[0].length = programChange ? 2 : 3', manual)
        for production_call in ('queueExpectedProgram', 'queueReturnedProgram', 'writeConsoleReturnState'):
            self.assertNotIn(production_call, manual)

        self.assertIn('startStop.enabled = programChange', rebuild)
        self.assertIn('isEqualToString:@"program_change"', auto)

    def test_integrated_simulator_has_no_profile_count_ceiling_or_index_signal_mapping(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        sync = source.split('- (void)syncSimulatorDevicesFromProfiles', 1)[1].split(
            '- (void)loadSimulatorDevices', 1
        )[0]
        rebuild = source.split('- (void)rebuildSimulatorDeviceRows', 1)[1].split(
            '- (void)createIntegratedSimulatorPanelInView:', 1
        )[0]
        create = source.split('- (void)createIntegratedSimulatorPanelInView:', 1)[1].split(
            '- (void)sendSimulatorMemory:', 1
        )[0]
        editor = source.split('- (void)addDeviceProfile:', 1)[1].split(
            '- (void)deleteDeviceProfile:', 1
        )[0]

        # Five or more eligible profiles follow the complete ordered source list.
        self.assertIn('for (NSDictionary *profile in self.deviceProfiles ?: @[])', sync)
        self.assertIn('[synced addObject:device]', sync)
        self.assertIn('for (NSNumber *channelNumber in self.simulatorDisplayOrder', sync)
        self.assertIn('device[@"test_only"] = @YES', sync)
        self.assertIn('[wantedIDs containsObject:simulatorID]', sync)
        for ceiling in ('.count == 2', '.count == 3', '.count == 4',
                        '.count < 2', '.count < 3', '.count < 4'):
            self.assertNotIn(ceiling, sync + rebuild)

        # Eligibility accepts PC, CC and Note; it is never inferred from device_4.
        for signal_type in ('program_change', 'control_change', 'note'):
            self.assertIn(f'@"{signal_type}"', sync)
        self.assertNotIn('device_4', sync + rebuild + editor)
        self.assertNotIn('note4', sync + rebuild + editor.lower())
        self.assertIn('@"signal_type": @"program_change"', editor)
        self.assertIn('@(midiChannel)', editor)

        # The document and scroller are driven by the actual simulator count.
        self.assertIn('NSUInteger deviceCount = visibleDeviceCount', rebuild)
        self.assertIn('CGFloat documentHeight = MAX(visibleHeight, rowsHeight)', rebuild)
        self.assertIn('self.simulatorDevicesScroll.hasVerticalScroller = documentHeight > visibleHeight', rebuild)
        self.assertIn('self.simulatorDevicesScroll.documentView = self.simulatorDeviceRows', create)

        # Per-device fields retain stable ID keys for all three value shapes.
        self.assertIn('self.simulatorValueFields[deviceID] = valueFields', rebuild)
        self.assertIn('self.simulatorMemoryFields[deviceID] = data1Field', rebuild)
        for key in ('@"memory"', '@"controller"', '@"value"', '@"note"', '@"velocity"'):
            self.assertIn(key, rebuild)

    def test_midi_test_bench_has_16_ui_channels_reordering_visibility_and_bounded_journal(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        sync = source.split('- (void)syncSimulatorDevicesFromProfiles', 1)[1].split(
            '- (void)loadSimulatorDevices', 1
        )[0]
        manual = source.split('- (void)sendSimulatorMemory:', 1)[1].split(
            '- (void)simulatorModeChanged:', 1
        )[0]
        journal = source.split('- (void)appendSimulatorJournalKind:', 1)[1].split(
            '- (void)clearSimulatorJournal:', 1
        )[0]

        self.assertIn('for (NSInteger channel = 1; channel <= 16; channel++)', source)
        self.assertIn('profileDevicesByChannel', sync)
        self.assertIn('@"test_channel_%ld"', sync)
        self.assertIn('device[@"test_only"] = @YES', sync)
        self.assertNotIn('[self.deviceProfiles addObject:', sync)
        self.assertIn('CLSimulatorDisplayOrderDefaultsKey', source)
        self.assertIn('CLSimulatorHiddenChannelsDefaultsKey', source)
        self.assertIn('CLSimulatorGenericSignalsDefaultsKey', source)
        self.assertIn('CLSimulatorDragButton', source)
        self.assertIn('performDragOperation:', source)
        self.assertIn('moveSimulatorChannel:channel toDisplayIndex:index', source)
        self.assertIn('toggleSimulatorRowVisibility:', source)
        self.assertIn('resetSimulatorDisplay:', source)
        self.assertIn('static const NSUInteger CLSimulatorJournalLimit = 500', source)
        self.assertIn('while (self.simulatorJournalEvents.count > CLSimulatorJournalLimit)', journal)
        self.assertIn('[self.simulatorJournalEvents removeObjectAtIndex:0]', journal)
        self.assertIn('appendSimulatorJournalKind:@"TX"', manual)
        self.assertNotIn('queueExpectedProgram', manual)
        self.assertNotIn('queueReturnedProgram', manual)
        self.assertNotIn('writeConsoleReturnState', manual)
        self.assertIn('self.simulatorMidiClient', manual)
        self.assertIn('self.simulatorMidiOutputPort', manual)
        self.assertNotIn('self.returnMonitorClient', manual)

        # A permanent legacy scroller reserves visible space whenever rows overflow,
        # and the list consumes additional height when the detached window grows.
        self.assertIn('self.simulatorDevicesScroll.autohidesScrollers = NO', source)
        self.assertIn('self.simulatorDevicesScroll.scrollerStyle = NSScrollerStyleLegacy', source)
        self.assertIn('NSViewWidthSizable | NSViewHeightSizable', source)
        self.assertIn('self.simulatorDevicesScroll.contentSize.height', source)

        # The large feedback area reports the last operator action; AUTO state is secondary.
        self.assertIn('@property NSTextField *simulatorActivityLabel', source)
        safety = source.split('- (void)updateSimulatorSafetyStatus', 1)[1].split(
            '- (void)showSimulatorOperatorMessage:', 1
        )[0]
        self.assertNotIn('self.simulatorStatusLabel.stringValue', safety)
        self.assertIn('@"%@ · MÉMOIRE %03ld ENVOYÉE"', manual)
        self.assertIn('@"%@ · CC %ld = %ld ENVOYÉ"', manual)
        self.assertIn('@"%@ · NOTE %ld · VEL %ld ENVOYÉE"', manual)
        self.assertIn('@"%@ · ÉCHEC D’ENVOI MIDI"', manual)
        self.assertIn('deviceName.uppercaseString', manual)

        # Compact right-side controls are explicit without changing their actions.
        self.assertIn('running ? @"■ Stop" : @"▶ Auto"', source)
        self.assertIn('hidden ? @"Afficher" : @"Masquer"', source)
        self.assertIn('Masquer cette ligne sans désactiver son profil', source)

    def test_rtp_timeout_explains_missing_remote_return_without_blame_on_iac(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        self.assertIn('Source expected Ableton (indépendante du RTP)', source)
        self.assertIn('indisponible (sans effet sur la liaison RTP)', source)
        self.assertIn('aucun simulateur de retour actif sur le Mac distant', source)

    def test_remote_simulator_accepts_bidirectional_rtp_endpoints_with_the_same_name(self):
        dashboard = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        engine = (TOOLS / "CLYamahaConsoleSimulator.m").read_text(encoding="utf-8")
        refresh = dashboard.split('- (void)refreshEndpoints', 1)[1].split('- (NSString *)toolPath:', 1)[0]
        endpoint_changed = dashboard.split('- (void)simulatorEndpointChanged:', 1)[1].split(
            '- (void)simulatorInputEndpointChanged:', 1
        )[0]
        input_changed = dashboard.split('- (void)simulatorInputEndpointChanged:', 1)[1].split(
            '- (NSTask *)launchSimulatorDevice:', 1
        )[0]
        transport = dashboard.split('- (BOOL)simulatorTransport:', 1)[1].split(
            '- (void)startSimulatorDevice:', 1
        )[0]
        self.assertIn('Endpoint RTP local introuvable', engine)
        self.assertIn('networkDestination = findEndpoint(NO, endpointSearchName)', engine)
        self.assertIn('networkSource = findEndpoint(YES, inputEndpointName)', engine)
        self.assertNotIn('caseInsensitiveCompare:endpointSearchName', engine)
        self.assertNotIn('Boucle MIDI refusée', engine)
        self.assertIn('[sources containsObject:savedInput] ? savedInput : @"Aucune"', refresh)
        self.assertNotIn('isEqualToString:endpoint', endpoint_changed)
        self.assertNotIn('isEqualToString:output', input_changed)
        self.assertNotIn('isEqualToString:requiredEndpoint', transport)

    def test_manual_program_change_preserves_channels_and_scene_offset(self):
        tester = (TOOLS / "CLMIDIRoundTripTester.m").read_text(
            encoding="utf-8"
        )
        dashboard = (TOOLS / "CLMIDINetworkDashboard.m").read_text(
            encoding="utf-8"
        )
        engine = (TOOLS / "CLYamahaConsoleSimulator.m").read_text(
            encoding="utf-8"
        )

        self.assertIn(
            'expectedProgram = (UInt8)(sceneNumber - 1)',
            tester
        )
        self.assertIn('0xC0 | (expectedChannel - 1)', tester)
        self.assertIn('UInt8 message[2]', tester)

        rebuild = dashboard.split(
            '- (void)rebuildSimulatorDeviceRows', 1
        )[1].split(
            '- (void)createIntegratedSimulatorPanelInView:', 1
        )[0]
        manual = dashboard.split(
            '- (void)sendSimulatorMemory:', 1
        )[1].split(
            '- (void)simulatorModeChanged:', 1
        )[0]

        # Channel comes from the selected dynamic device.
        self.assertIn(
            'NSInteger channel = [device[@"channel"] integerValue]',
            rebuild
        )
        self.assertIn('send.tag = channel', rebuild)
        self.assertIn(
            'NSInteger channel = device ? [device[@"channel"] integerValue] : sender.tag',
            manual
        )

        # Scene memory remains human 1-128, MIDI Program Change remains zero-based.
        self.assertIn(
            'programChange ? data1Input - 1 : data1Input',
            manual
        )
        self.assertIn('programChange ? 0xC0', manual)
        self.assertIn('((channel - 1) & 0x0F)', manual)

        self.assertIn(
            '(UInt8)(0xC0 | (acceptedChannel - 1))',
            engine
        )
        self.assertIn('(UInt8)(manualScene - 1)', engine)

    def test_dashboard_never_falls_back_to_ableton_for_expected_console_title(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        method = source.rsplit("- (void)updateConsoleReturnCards", 1)[1].split(
            "- (void)refreshAbletonSceneTitle", 1
        )[0]
        self.assertIn('expected[@"expected_title"]', method)
        self.assertIn('@"Titre non résolu"', method)
        self.assertNotIn("currentAbletonSceneTitle", method)

    def test_dashboard_cards_render_the_canonical_status_model(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        method = source.rsplit("- (void)updateConsoleReturnCards", 1)[1].split(
            "- (void)refreshAbletonSceneTitle", 1
        )[0]
        for field in (
            "expected_scene_memory", "expected_title", "expected_program_source",
            "returned_scene_memory", "returned_title", "returned_program_source",
            "title_offset", "expected_title_lookup_memory", "returned_title_lookup_memory",
            "validation_status", "expected_activated_at", "last_return_age_seconds", "confirmation_latency_ms",
        ):
            self.assertIn(f'expected[@"{field}"]', method)
        for status in ("confirmed", "mismatch", "stale", "local_fallback", "unavailable"):
            self.assertIn(f'@"{status}"', method)
        self.assertIn('@"✓ Confirmé par la console"', method)
        self.assertIn('@"En attente du retour"', method)
        self.assertIn('@"recall_waiting"', method)
        self.assertIn('elapsedSinceExpected < 4.0', method)
        self.assertIn('!mismatch', method)
        self.assertIn('[visualState isEqualToString:@"recall_waiting"]', method)
        self.assertIn('@"clVisualRecallTimerKey"', method)
        self.assertIn('4.0 - elapsedSinceExpected', method)
        self.assertNotIn("date.timeIntervalSinceNow", method)

    def test_network_manager_prefers_canonical_device_states_from_status(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        method = source.split("- (void)refreshAbletonSceneTitle {", 1)[1].split(
            "- (void)rebuildConsoleLibraryRows", 1
        )[0]

        self.assertIn('payload[@"device_states"]', method)
        self.assertIn('deviceStates[@"console_a"]', method)
        self.assertIn('deviceStates[@"console_b"]', method)
        self.assertIn('NSDictionary *cl5 = consoleA ?:', method)
        self.assertIn('NSDictionary *ql1 = consoleB ?:', method)

        # Le vieux midi_console reste volontairement un fallback seulement.
        self.assertIn('payload[@"midi_console"]', method)
        self.assertLess(
            method.index('deviceStates[@"console_a"]'),
            method.index('midiConsole[@"cl5"]'),
        )

    def test_local_mode_keeps_physical_return_monitor_canonical(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")

        setup = source.split("- (void)setupPassiveReturnMonitor {", 1)[1].split(
            "- (void)recordIsolatedDeviceTestProgram:", 1
        )[0]

        self.assertIn(
            "[self selectPassiveReturnSourceNamed:preferredReturnSource]",
            setup,
        )
        self.assertNotIn(
            "if (self.localReturnMode) self.returnMonitorStatus = localStatus",
            setup,
        )
        self.assertIn(
            "self.returnMonitorSourceName ?: (preferred ?: @\"aucune\")",
            source,
        )

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

    def test_ql1_visual_identity_keeps_configurable_cyan_variants(self):
        skins = (ROOT / "static" / "cl-skins.css").read_text(encoding="utf-8").lower()
        ql1_skin_values = [
            line.split(":", 1)[1].strip().rstrip(";")
            for line in skins.splitlines()
            if "--cl-skin-ql1:" in line
        ]
        self.assertTrue(ql1_skin_values)
        self.assertGreater(len(set(ql1_skin_values)), 1)
        self.assertTrue(all(value.startswith("#") for value in ql1_skin_values))

        show = (ROOT / "launcher_control.py").read_text(encoding="utf-8").lower()
        self.assertIn("palette:{base:'#63c7d4',accent:'#3e9eac'}", show)

        visual = (ROOT / "static" / "midi-return-visual.js").read_text(encoding="utf-8").lower()
        self.assertIn("console_b: {base: '#63c7d4', accent: '#3e9eac'}", visual)

        for template_name in ("index.html", "arrangement.html"):
            template = (ROOT / "templates" / template_name).read_text(encoding="utf-8").lower()
            self.assertIn("renderdevicecards", template)

        dashboard = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")

        # La palette QL1 historique reste cyan dans le profil par défaut,
        # mais le renderer natif consomme désormais la palette configurée.
        self.assertIn('#63C7D4', dashboard)
        self.assertIn('#3E9EAC', dashboard)
        self.assertIn('profile[@"palette"]', dashboard)
        self.assertIn('deviceColorFromHex:palette[@"base"]', dashboard)
        self.assertIn('deviceColorFromHex:palette[@"accent"]', dashboard)

        # Les anciennes identités vertes restent interdites.
        self.assertNotIn("colorWithRed:0.18 green:0.52 blue:0.29", dashboard)
        self.assertNotIn("colorWithRed:0.247 green:0.608 blue:0.349", dashboard)

    def test_devices_editor_is_dynamic_persistent_and_protects_legacy_devices(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        editor = source.split("#pragma mark - Device Profiles editor", 1)[1].split(
            "- (void)windowWillClose:", 1
        )[0]
        self.assertIn('CLDeviceConfigurationPath', source)
        self.assertIn('@"schema_version": @(CLDeviceSchemaVersion)', editor)
        self.assertIn('for (NSUInteger index = 0; index < self.deviceProfiles.count; index++)', editor)
        self.assertIn('action:@selector(addDeviceProfile:)', editor)
        self.assertIn('@"enabled": @NO', editor)
        self.assertIn('console_a', editor)
        self.assertIn('console_b', editor)
        self.assertIn('NSDataWritingAtomic', editor)
        self.assertIn('Configuration appliquée', editor)
        self.assertIn('Les devices historiques peuvent être désactivés, pas supprimés', editor)
        self.assertIn('Restaurer CL5 / QL1 par défaut ?', editor)

    def test_devices_editor_manages_generic_console_library_ids(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        editor = source.split("#pragma mark - Device Profiles editor", 1)[1].split(
            "- (void)windowWillClose:", 1
        )[0]
        populate = editor.split("- (void)populateDeviceEditorFields", 1)[1].split(
            "- (NSArray<NSString *> *)cleanAliasesFromString:", 1
        )[0]
        commit = editor.split("- (BOOL)commitVisibleDeviceFields", 1)[1].split(
            "- (void)saveDeviceProfiles:", 1
        )[0]
        validation = editor.split("- (NSString *)validateDeviceProfiles", 1)[1].split(
            "- (BOOL)commitVisibleDeviceFields", 1
        )[0]
        signal_change = editor.split("- (void)deviceSignalChanged:", 1)[1].split(
            "- (void)updateDeviceTestFieldsForSelectedProfile", 1
        )[0]

        self.assertIn('@property NSTextField *deviceLibraryField;', source)
        self.assertIn('@"Bibliothèque"', editor)
        self.assertIn('device[@"library"]', populate)
        self.assertIn('self.deviceLibraryField.stringValue', populate)
        self.assertIn('stringByTrimmingCharactersInSet', commit)
        self.assertIn('lowercaseString', commit)
        self.assertIn('device[@"library"] = libraryID.length ? libraryID : NSNull.null;', commit)
        self.assertIn('^[a-z0-9][a-z0-9_-]{0,63}$', validation)
        self.assertIn('bibliothèque invalide', validation)
        self.assertIn('libraryID = @"cl5"', commit)
        self.assertIn('libraryID = @"ql1"', commit)
        self.assertIn('Non utilisée pour CC/Note · valeur conservée', signal_change)
        self.assertIn('@"library": NSNull.null', editor)
        self.assertIn('[self refreshProfileDrivenViews];', editor)
        self.assertIn('[self rebuildConsoleLibraryRows];', source.split(
            '- (void)refreshProfileDrivenViews {', 1
        )[1].split('- (void)updateConsoleReturnCards {', 1)[0])

        library_rows = source.split('- (void)rebuildConsoleLibraryRows {', 1)[1].split(
            '- (void)updateConsoleLibrariesFromStatus:', 1
        )[0]
        self.assertIn('for (NSDictionary *device in self.deviceProfiles)', library_rows)
        self.assertIn('program_change', library_rows)
        self.assertIn('device[@"library"]', library_rows)
        self.assertNotIn('@[@"cl5", @"ql1"]', library_rows)

    def test_isolated_device_test_bench_never_calls_production_state_writers(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        bench = source.split('- (void)refreshIsolatedDeviceTestEndpoints:', 1)[1].split(
            '- (void)windowWillClose:', 1
        )[0]
        self.assertIn('CLIsProtectedDeviceTestEndpoint', bench)
        self.assertIn('MIDIOutputPortCreate', bench)
        self.assertIn('MIDIInputPortCreate', bench)
        self.assertIn('MIDIPortConnectSource', bench)
        self.assertIn('MIDISend', bench)
        self.assertIn('TEST TX', bench)
        self.assertIn('TEST RX', bench)
        self.assertIn('ROUND TRIP TEST', bench)
        self.assertNotIn('queueExpectedProgram:', bench)
        self.assertNotIn('queueReturnedProgram:', bench)
        self.assertNotIn('writeConsoleReturnState', bench)
        self.assertNotIn('expected_activated_at', bench)
        self.assertNotIn('validation_status', bench)

    def test_device_test_bench_has_real_round_trip_and_complete_endpoint_diagnostic(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        bench = source.split('- (void)refreshIsolatedDeviceTestEndpoints:', 1)[1].split('- (void)windowWillClose:', 1)[0]
        isolated_parser = source.split('static void CLIsolatedDeviceTestRead', 1)[1].split(
            'static NSString *CLMidiAgeDescription', 1
        )[0]
        self.assertIn('CLAllMIDIEndpointInventory', source)
        self.assertIn('Tous les ports MIDI…', source)
        self.assertIn('kMIDIPropertyUniqueID', source)
        self.assertIn('kMIDIPropertyOffline', source)
        self.assertIn('kMIDIPropertyManufacturer', source)
        self.assertIn('kMIDIPropertyDriverOwner', source)
        self.assertIn('ROUND TRIP TEST EN ATTENTE', bench)
        self.assertIn('ROUND TRIP TEST PASS', source)
        self.assertIn('ROUND TRIP TEST FAIL · timeout 2,0 s', bench)
        self.assertIn('deviceRoundTripGeneration', bench)
        self.assertIn('CLDeviceTestMIDINotify', source)
        self.assertIn('delegate.deviceTestRunningStatus', isolated_parser)
        self.assertIn('recordIsolatedDeviceTestMessageType:', isolated_parser)
        self.assertIn('@"program_change"', isolated_parser)
        self.assertIn('@"control_change"', isolated_parser)
        self.assertIn('@"note_on"', isolated_parser)
        self.assertIn('@"note_off"', isolated_parser)
        self.assertNotIn('queueExpectedProgram', isolated_parser)
        self.assertNotIn('queueReturnedProgram', isolated_parser)
        self.assertNotIn('writeConsoleReturnState', isolated_parser)

    def test_periodic_endpoint_inventory_never_blocks_the_cocoa_main_thread(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        refresh = source.split('- (void)refreshEndpoints {', 1)[1].split(
            '- (void)applyEndpointSnapshotWithSources:', 1
        )[0]
        implementation = source.split('@implementation CLNetworkDelegate', 1)[1]
        apply_snapshot = implementation.split('- (void)applyEndpointSnapshotWithSources:', 1)[1].split(
            '- (NSString *)toolPath:', 1
        )[0]
        self.assertIn('dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)', refresh)
        self.assertIn('NSArray<NSString *> *sources = EndpointNames(YES);', refresh)
        self.assertIn('NSArray<NSString *> *destinations = EndpointNames(NO);', refresh)
        self.assertIn('dispatch_get_main_queue()', refresh)
        self.assertNotIn('EndpointNames(', apply_snapshot)
        self.assertIn('if (self.ownsPassiveReturnMonitor)', apply_snapshot)

    def test_device_editor_preserves_legacy_channels_and_test_permissions(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        endpoint_refresh = source.split('- (void)refreshIsolatedDeviceTestEndpoints:', 1)[1].split(
            '- (void)showAllMidiEndpoints:', 1
        )[0]
        self.assertIn('CL5 historique doit rester sur le canal MIDI 1', source)
        self.assertIn('QL1 historique doit rester sur le canal MIDI 2', source)
        self.assertIn('self.deviceTXCheck', source)
        self.assertIn('self.deviceRXCheck', source)
        self.assertIn('TX désactivé pour cet appareil', source)
        self.assertIn('RX désactivé pour cet appareil', source)
        self.assertIn('if (selectedDestination.length && [self.deviceTestDestinationMenu itemWithTitle:selectedDestination])', endpoint_refresh)
        self.assertIn('if (selectedSource.length && [self.deviceTestSourceMenu itemWithTitle:selectedSource])', endpoint_refresh)

    def test_verification_bundle_never_rewrites_production_monitor_launch_agent(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        self.assertIn('hasSuffix:@".verification"', source)
        self.assertIn('runningFromAppBundle && !verificationBundle', source)
        self.assertIn('bundle Verification isolé : LaunchAgent de production inchangé', source)

    def test_dashboard_clarifies_mode_devices_connection_and_simulator_actions(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        self.assertIn('@"Mode appliqué par CL Audio Show Control"', source)
        self.assertIn('@"CL Audio Show Control indisponible · mode affiché conservé localement"', source)
        self.assertIn('@"CIBLE ABLETON DISTANTE (RTP)"', source)
        self.assertIn('self.connectButton.title = local ? @"Non requis" : @"Connecter"', source)
        self.assertIn('self.connectButton.title = self.localReturnMode ? @"Non requis" : @"Connecter"', source)
        self.assertIn('scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable', source)
        self.assertIn('self.assistantReturnPanel.frame = NSMakeRect(16, 90, 468, 215)', source)
        self.assertIn('self.assistantDevicesScroll.frame = self.assistantReturnPanel.bounds', source)
        self.assertIn('visibleDevices.count == 1 ? 1 : 2', source)
        self.assertIn('visibleDevices.count <= 2 ? 106.0 : 100.0', source)
        self.assertIn('self.assistantDevicesButton.frame = NSMakeRect(246, 527 + offset, 106, 30)', source)
        self.assertIn('@"⚙  Appareils…"', source)
        self.assertEqual(source.count('action:@selector(openDevicesEditor:)'), 1)
        self.assertIn('documentHeight - scroll.contentView.bounds.size.height', source)
        self.assertIn('self.consoleLibrariesPanel.hidden = !detailed', source)
        self.assertIn('self.simulatorWindowButton.hidden = !detailed', source)
        self.assertIn('action:@selector(openSimulatorWindow:)', source)
        self.assertIn('self.assistantDevicesButton.hidden = NO', source)
        self.assertIn('self.assistantDevicesButton.enabled = YES', source)
        self.assertIn('positioned:NSWindowAbove', source)
        self.assertEqual(source.count('addSubview:self.assistantDevicesButton'), 1)
        self.assertIn('@"APPAREILS SUIVIS"', source)
        self.assertIn('@"Mode test actif · %lu appareil%@ simulé%@"', source)
        self.assertIn('@"%@ · %@", verdict, mode', source)
        self.assertIn('self.expectedDeviceStates[deviceID]', source)
        self.assertIn('self.returnedDeviceStates[deviceID]', source)
        self.assertIn('self.simulatorStartButton.title = @"REDÉMARRER"', source)
        self.assertIn('self.simulatorStartButton.title = @"DÉMARRER"', source)
        self.assertIn('self.simulatorStopAllButton.enabled = NO', source)

    def test_detailed_layout_compacts_mode_and_technical_panels_for_five_devices(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        presentation = source.split('- (void)applyPresentationMode {', 1)[1].split(
            '- (void)layoutAssistantViewForRTPMode:', 1
        )[0]
        simulator = source.split('- (void)rebuildSimulatorDeviceRows', 1)[1].split(
            '- (void)createIntegratedSimulatorPanelInView:', 1
        )[0]

        self.assertIn('CGFloat modePanelHeight = 58.0', presentation)
        self.assertIn('self.technicalPanel.frame = NSMakeRect(16, 47, 468, 132)', presentation)
        self.assertIn('self.simulatorWindowButton.frame = NSMakeRect(170, actionsY, 160, 32)', presentation)
        self.assertIn('self.consoleLibrariesPanel.frame = NSMakeRect(16, actionsY + 50.0 + returnsHeight, 468, 116)', presentation)
        self.assertIn('self.testPanel.frame = NSMakeRect(16, actionsY + 59.0 + returnsHeight + 116.0, 468, 96)', presentation)
        self.assertIn('CGFloat offset = self.localReturnMode ? 0.0 : 104.0', presentation)
        self.assertIn('self.connectButton.frame = NSMakeRect(364, 5, 92, 30)', presentation)
        self.assertIn('self.operatingModeReasonLabel.hidden = detailed', presentation)
        self.assertIn('@"RETOURS PROGRAM CHANGE"', source)
        return_cards = source.split('- (void)rebuildProgramChangeReturnCards {', 1)[1].split(
            '- (void)updateConsoleReturnCards {', 1
        )[0]
        self.assertIn('for (NSDictionary *profile in self.deviceProfiles ?: @[])', return_cards)
        self.assertIn('profile[@"protocol"]', return_cards)
        self.assertIn('isEqualToString:@"midi"', return_cards)
        self.assertIn('profile[@"signal_type"]', return_cards)
        self.assertIn('isEqualToString:@"program_change"', return_cards)
        self.assertNotIn('console_a', return_cards)
        self.assertNotIn('console_b', return_cards)
        self.assertIn('index / 3', return_cards)
        self.assertIn('index % 3', return_cards)
        self.assertIn('palette[@"accent"]', return_cards)
        self.assertIn('programLabel.stringValue = hasReturn', source)
        self.assertIn('@"Aucun retour"', source)
        self.assertIn('@"Retour frais"', source)
        self.assertIn('@"Retour ancien"', source)
        self.assertIn('@"Mismatch"', source)
        self.assertIn('@"RTP non requis"', source)
        self.assertIn('@"Retour MIDI local via port dédié."', source)
        self.assertIn('self.remoteTargetTitleLabel.hidden = self.localReturnMode', presentation)
        self.assertIn('self.targetMenu.hidden = self.localReturnMode', presentation)
        self.assertIn('self.connectButton.hidden = self.localReturnMode', presentation)
        self.assertIn('self.returnModeMenu.frame = self.localReturnMode', presentation)
        self.assertIn('? NSMakeRect(116, 13, 164, 32)', presentation)
        self.assertIn('colorWithRed:0.58 green:0.34 blue:0.19', source)
        self.assertIn('self.testPanel.hidden = !rtpMode', source)
        self.assertIn('self.settingsButton.frame = NSMakeRect(16, actionsY, 146, 32)', presentation)
        self.assertIn('self.refreshButton.frame = NSMakeRect(338, actionsY, 146, 32)', presentation)
        self.assertIn('colorWithRed:0.08 green:0.43 blue:0.39', source)

        self.assertIn('const CGFloat rowHeight = 28.0', simulator)
        self.assertIn('const CGFloat rowSpacing = 3.0', simulator)
        self.assertIn('self.simulatorDevicesScroll.contentSize.height', simulator)
        self.assertIn('documentHeight > visibleHeight', simulator)

    def test_program_change_cards_drop_stale_profiles_on_every_device_edit_cycle(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        rebuild = source.split('- (void)rebuildProgramChangeReturnCards {', 1)[1].split(
            '- (void)refreshProfileDrivenViews {', 1
        )[0]
        refresh = source.split('- (void)refreshProfileDrivenViews {', 1)[1].split(
            '- (void)updateConsoleReturnCards {', 1
        )[0]
        editor = source.split('- (void)saveDeviceProfiles:', 1)[1].split(
            '- (void)updateDeviceTestFieldsForSelectedProfile', 1
        )[0]

        # Rebuilding derives every card from the current canonical profiles and
        # first removes both stale AppKit views and stale dictionary references.
        self.assertIn('for (NSView *view in self.programChangeReturnsPanel.subviews.copy)', rebuild)
        self.assertIn('[view removeFromSuperview]', rebuild)
        self.assertIn('self.programChangeReturnViews = [NSMutableDictionary dictionary]', rebuild)
        self.assertIn('for (NSDictionary *profile in self.deviceProfiles ?: @[])', rebuild)
        self.assertIn('isEqualToString:@"program_change"', rebuild)
        self.assertIn('isEqualToString:@"midi"', rebuild)
        self.assertIn('self.programChangeReturnViews[deviceID]', rebuild)

        # Save, base reset, dynamic deletion and signal changes share one refresh.
        self.assertIn('[self rebuildProgramChangeReturnCards]', refresh)
        self.assertIn('[self updateConsoleReturnCards]', refresh)
        self.assertGreaterEqual(editor.count('[self refreshProfileDrivenViews]'), 4)
        restore = editor.split('- (void)restoreDefaultDeviceProfiles:', 1)[1].split(
            '- (void)addDeviceProfile:', 1
        )[0]
        delete = editor.split('- (void)deleteDeviceProfile:', 1)[1].split(
            '- (void)deviceProfileChanged:', 1
        )[0]
        signal = editor.split('- (void)deviceSignalChanged:', 1)[1]
        self.assertLess(restore.index('self.deviceProfiles ='), restore.index('[self refreshProfileDrivenViews]'))
        self.assertLess(delete.index('[self.deviceProfiles removeObject:device]'), delete.index('[self refreshProfileDrivenViews]'))
        self.assertLess(signal.index('device[@"signal_type"] = signalType'), signal.index('[self refreshProfileDrivenViews]'))

        for forbidden in ('device_3', 'device_4', 'device_5'):
            self.assertNotIn(forbidden, rebuild + refresh)

    def test_secondary_ui_uses_only_fresh_published_local_return_status(self):
        source = (TOOLS / "CLMIDINetworkDashboard.m").read_text(encoding="utf-8")
        loader = source.split('- (void)loadPublishedConsoleReturnState', 1)[1].split(
            '- (void)writeConsoleReturnState', 1
        )[0]
        self.assertIn('publishedStateIsFresh', loader)
        self.assertIn('<= 6.0', loader)
        self.assertIn('@"local_dedicated"', loader)
        self.assertIn('CLLocalReturnEndpointName', loader)
        self.assertIn('return_monitor_status', loader)
        self.assertIn('- (BOOL)localReturnIsAvailable', loader)
        self.assertIn('!self.ownsPassiveReturnMonitor && self.publishedLocalReturnAvailable', loader)


if __name__ == "__main__":
    unittest.main()
