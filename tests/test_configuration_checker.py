import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools" / "cl_midi_network"


class ConfigurationCheckerTests(unittest.TestCase):
    def test_checker_has_separate_profile_inspector_validator_and_report_layers(self):
        header = (TOOLS / "CLConfigurationChecker.h").read_text()
        for name in (
            "CLConfigurationProfile",
            "CLConfigurationInspector",
            "CLConfigurationValidator",
            "CLConfigurationReport",
        ):
            self.assertIn(name, header)

    def test_profile_is_versioned_validated_and_stored_outside_the_repository(self):
        source = (TOOLS / "CLConfigurationProfile.m").read_text()
        self.assertIn('@"schema_version": @1', source)
        self.assertIn('schema_version doit valoir 1', source)
        self.assertIn('NSApplicationSupportDirectory', source)
        self.assertIn('@"CL Audio"', source)
        self.assertIn('@"Configuration Profiles"', source)
        self.assertIn('overwrite:(BOOL)overwrite', source)
        self.assertIn('Un profil portant ce nom existe déjà', source)

    def test_peer_session_bonjour_and_local_endpoint_are_distinct(self):
        profile = (TOOLS / "CLConfigurationProfile.m").read_text()
        validator = (TOOLS / "CLConfigurationValidator.m").read_text()
        for key in ("local_session_name", "local_endpoint", "bonjour_name", "expected_peer"):
            self.assertIn(key, profile)
        self.assertIn('peer distant attendu, jamais au nom de l’endpoint local', validator)

    def test_server_profile_uses_local_dedicated_iac_scenario(self):
        profile = (TOOLS / "CLConfigurationProfile.m").read_text()
        validator = (TOOLS / "CLConfigurationValidator.m").read_text()
        self.assertIn('remote ? @"rtp" : @"iac"', profile)
        self.assertIn('remote ? @"" : @"CL MIDI Return Test"', profile)
        self.assertIn('remote ? @"" : @"local_dedicated"', profile)
        self.assertIn('BOOL rtpScenario = !server ||', validator)
        self.assertIn('if (rtpScenario)', validator)
        self.assertIn('@"endpoint local de retour"', validator)
        self.assertNotIn('Sélectionner l’endpoint RTP local « %@ ».', validator)

    def test_remote_profile_keeps_rtp_simulator_checks(self):
        profile = (TOOLS / "CLConfigurationProfile.m").read_text()
        validator = (TOOLS / "CLConfigurationValidator.m").read_text()
        self.assertIn('remote ? @"rtp" : @"iac"', profile)
        self.assertIn('rtpScenario ? ([sourceNames containsObject:endpoint] && [destinationNames containsObject:endpoint])', validator)
        for title in ("Session RTP locale", "Nom Bonjour local", "Peer RTP attendu"):
            self.assertIn(title, validator)

    def test_saved_local_iac_profile_does_not_adopt_rtp_endpoint(self):
        app = (TOOLS / "CLConfigurationCheckerApp.m").read_text()
        self.assertIn('[simulator[@"transport"] isEqualToString:@"rtp"]', app)

    def test_inspector_is_read_only_and_collects_required_system_state(self):
        source = (TOOLS / "CLConfigurationInspector.m").read_text()
        for expected in (
            "MIDIGetNumberOfSources",
            "kMIDIPropertyUniqueID",
            "kMIDIPropertyManufacturer",
            "MIDINetworkSession.defaultSession",
            'CLRun(@"/bin/ps"',
            'CLRun(@"/usr/sbin/lsof"',
            "proc_pidpath",
            "http://127.0.0.1:5050/status",
        ):
            self.assertIn(expected, source)
        for forbidden in ("addConnection:", "MIDISend(", "terminate]", "session.enabled =", "kill("):
            self.assertNotIn(forbidden, source)

    def test_validator_detects_translocation_dev_builds_ports_and_simulator_mismatch(self):
        source = (TOOLS / "CLConfigurationValidator.m").read_text()
        for expected in (
            "App Translocation",
            "Build de développement active",
            "Doublon suspect",
            "@5050",
            "@11000",
            "@11001",
            "@63123",
            "CLYamahaConsoleSimulator",
            "--endpoint",
            "--channel",
            "--transport",
            "--delay-ms",
            "Le processus doit utiliser un endpoint RTP présent sur ce Mac",
            "getaddrinfo",
            "expected_midi_program",
            "returned_midi_program",
            "expected == NSNull.null",
            "CLCheckLevelError",
            "NON PRÊT",
        ):
            self.assertIn(expected, source)

    def test_generic_simulator_channels_follow_canal_label(self):
        source = (TOOLS / "CLConfigurationValidator.m").read_text()
        self.assertIn('caseInsensitiveCompare:@"CL5"', source)
        self.assertIn('caseInsensitiveCompare:@"QL1"', source)
        self.assertIn('^Canal\\\\s+([1-9]|1[0-6])$', source)
        self.assertIn('expectedChannel = [label substringWithRange:[match rangeAtIndex:1]]', source)

    def test_simulator_argument_parser_preserves_unquoted_values_with_spaces(self):
        source = (TOOLS / "CLConfigurationValidator.m").read_text()
        self.assertIn('regularExpressionWithPattern:@"\\\\s--[[:alnum:]][[:alnum:]-]*', source)
        self.assertIn("substringToIndex:boundary.location == NSNotFound ? tail.length : boundary.location", source)
        self.assertNotIn("componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet].firstObject", source)

    def test_same_named_rtp_source_and_destination_form_a_valid_pair(self):
        source = (TOOLS / "CLConfigurationValidator.m").read_text()
        self.assertIn("[sourceNames containsObject:expectedEndpoint]", source)
        self.assertIn("[destinationNames containsObject:expectedEndpoint]", source)
        self.assertNotIn("sourceNames intersectsSet:destinationNames", source)

    def test_processes_are_counted_by_executable_not_bundle_path(self):
        inspector = (TOOLS / "CLConfigurationInspector.m").read_text()
        validator = (TOOLS / "CLConfigurationValidator.m").read_text()
        self.assertIn('@"executable": executable', inspector)
        self.assertIn('processNames[executable]', validator)
        self.assertIn('@"CLMIDINetworkGuardian": @"CLMIDINetworkGuardian"', validator)
        self.assertNotIn('if ([command containsString:name]) counts[name]', validator)

    def test_return_states_use_status_and_age_without_false_mismatch(self):
        source = (TOOLS / "CLConfigurationValidator.m").read_text()
        for expected in (
            'console[@"validation_status"]',
            'console[@"last_return_age_seconds"]',
            '@"confirmed"',
            '@"mismatch"',
            '@"stale"',
            '@"waiting"',
            '@"unavailable"',
            'Retour périmé',
            'if (!expected) validation = @"unavailable"',
        ):
            self.assertIn(expected, source)

    def test_canonical_title_libraries_replace_desktop_clf_requirements(self):
        profile = (TOOLS / "CLConfigurationProfile.m").read_text()
        inspector = (TOOLS / "CLConfigurationInspector.m").read_text()
        validator = (TOOLS / "CLConfigurationValidator.m").read_text()
        for filename in ("CL5.titles.json", "QL1.titles.json"):
            self.assertIn(filename, profile)
        self.assertNotIn("Desktop/CL5.CLF", profile)
        self.assertNotIn("Desktop/ql1.CLF", profile)
        for field in ('@"entries"', '@"source_format"', '@"source_name"', '@"migrated_from"', '@"entry_count"'):
            self.assertIn(field, inspector)
        self.assertIn('Bibliothèques de titres', validator)

    def test_monitor_state_and_degraded_mode_are_explicit(self):
        source = (TOOLS / "CLConfigurationValidator.m").read_text()
        for expected in (
            'expected_monitor_source', 'expected_monitor_status',
            'return_monitor_source', 'return_monitor_status',
            'Expected monitor', 'Return monitor',
            'degraded_ableton_clip_name', 'mode dégradé',
        ):
            self.assertIn(expected, source)

    def test_profiles_strip_transient_program_change_observations(self):
        profile = (TOOLS / "CLConfigurationProfile.m").read_text()
        app = (TOOLS / "CLConfigurationCheckerApp.m").read_text()
        for transient in (
            'operational_state', 'server_status', 'midi_console', 'captured_at',
            'expected_midi_program', 'returned_midi_program',
            'last_return_age_seconds', 'validation_status',
        ):
            self.assertIn(transient, profile)
        self.assertIn('CLPersistentProfileValues(values)', profile)
        self.assertIn('console_return_mode', app)
        self.assertIn('console_return_source', app)

    def test_ui_exposes_safe_check_and_profile_workflow(self):
        source = (TOOLS / "CLConfigurationCheckerApp.m").read_text()
        for expected in (
            "CL MIDI & RTP DIAGNOSTIC",
            "ABLETON LOCAL",
            "ABLETON DISTANT",
            "VÉRIFIER",
            "ENREGISTRER LE PROFIL",
            "OUVRIR UN PROFIL",
            "COPIER TOUT",
            "EXPORTER TEXTE",
            "Lecture seule",
            "--inspect-json",
        ):
            self.assertIn(expected, source)
        self.assertNotIn('MAC SERVEUR', source)
        self.assertNotIn('DUPLIQUER', source)
        self.assertNotIn('EXPORTER JSON', source)

    def test_text_report_can_be_copied_or_exported_without_changing_the_profile(self):
        source = (TOOLS / "CLConfigurationCheckerApp.m").read_text()
        for expected in (
            "textReport",
            "self.details.string",
            "NSPasteboard.generalPasteboard",
            "NSPasteboardTypeString",
            "exportTextReport:",
            "CL MIDI & RTP Diagnostic.txt",
            "NSUTF8StringEncoding",
        ):
            self.assertIn(expected, source)
        self.assertIn("[[self textReport] writeToURL:panel.URL", source)

    def test_header_displays_the_bundled_paradis_latin_logo(self):
        source = (TOOLS / "CLConfigurationCheckerApp.m").read_text()
        release = (ROOT / "scripts" / "build_release.sh").read_text()
        self.assertIn('pathForResource:@"paradis_latin_logo" ofType:@"jpg"', source)
        self.assertIn("NSImageScaleProportionallyUpOrDown", source)
        self.assertIn("NSImageAlignRight", source)
        self.assertIn('paradis_latin_logo.jpg', release)

    def test_checker_is_built_and_packaged_with_network_tools(self):
        build = (TOOLS / "build.sh").read_text()
        release = (ROOT / "scripts" / "build_release.sh").read_text()
        console = (ROOT / "scripts" / "build_midi_console_package.sh").read_text()
        for source in (build, release, console):
            self.assertIn("CLAudioConfigurationChecker", source)


if __name__ == "__main__":
    unittest.main()
