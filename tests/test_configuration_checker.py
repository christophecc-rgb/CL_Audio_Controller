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
            "Le processus doit utiliser un endpoint présent sur ce Mac",
            "getaddrinfo",
            "expected_midi_program",
            "returned_midi_program",
            "expected == NSNull.null",
            "CLCheckLevelError",
            "NON PRÊT",
        ):
            self.assertIn(expected, source)

    def test_ui_exposes_safe_check_and_profile_workflow(self):
        source = (TOOLS / "CLConfigurationCheckerApp.m").read_text()
        for expected in (
            "CL AUDIO CONFIGURATION CHECKER",
            "VÉRIFIER",
            "SAUVEGARDER COMME PROFIL",
            "CHARGER / IMPORTER",
            "DUPLIQUER",
            "EXPORTER JSON",
            "Lecture seule",
            "--inspect-json",
        ):
            self.assertIn(expected, source)

    def test_checker_is_built_and_packaged_with_network_tools(self):
        build = (TOOLS / "build.sh").read_text()
        release = (ROOT / "scripts" / "build_release.sh").read_text()
        console = (ROOT / "scripts" / "build_midi_console_package.sh").read_text()
        for source in (build, release, console):
            self.assertIn("CLAudioConfigurationChecker", source)


if __name__ == "__main__":
    unittest.main()
