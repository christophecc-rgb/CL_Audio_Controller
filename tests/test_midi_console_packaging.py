import plistlib
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class MidiConsolePackagingTests(unittest.TestCase):
    def test_installer_uses_user_library_and_preserves_existing_installation(self):
        source = (ROOT / "packaging" / "Installer_CL_MIDI_Console.command").read_text()
        self.assertIn("Music/Ableton/User Library/Presets/MIDI Effects/Max MIDI Effect", source)
        self.assertIn("backup_existing", source)
        self.assertNotIn("sudo", source)

    def test_uninstaller_moves_only_known_targets_to_trash(self):
        source = (ROOT / "packaging" / "Desinstaller_CL_MIDI_Console.command").read_text()
        self.assertIn('TARGETS=(', source)
        self.assertIn('mv "$target" "$destination"', source)
        self.assertNotIn("rm -rf", source)

    def test_package_builder_contains_source_binary_and_reproducibility_files(self):
        source = (ROOT / "scripts" / "build_midi_console_package.sh").read_text()
        for required in (
            "CL MIDI Console Monitor.amxd",
            "CL MIDI Console Monitor.maxpat",
            "CLMidiConsoleDisplay.js",
            "CLMidiConsoleConfirmation.js",
            "CLMIDIRoundTripTester",
            "SHA256SUMS.txt",
        ):
            self.assertIn(required, source)
        self.assertIn("hdiutil create", source)
        self.assertIn("ditto -c -k", source)

    def test_complete_suite_installer_offers_midi_console_as_a_separate_component(self):
        source = (ROOT / "packaging" / "Installer_Toute_La_Suite_CL.command").read_text()
        self.assertIn("CL MIDI Console uniquement", source)
        self.assertIn("INSTALL_MIDI_CONSOLE", source)
        self.assertIn("Presets/MIDI Effects/Max MIDI Effect/CL MIDI Console Monitor", source)
        self.assertIn("CL MIDI Network Assistant.app", source)
        self.assertIn('"midi-console"', source)

    def test_complete_suite_uninstaller_limits_midi_console_removal_to_known_targets(self):
        source = (ROOT / "packaging" / "Desinstaller_La_Suite_CL.command").read_text()
        self.assertIn("UNINSTALL_MIDI_CONSOLE", source)
        self.assertIn("Presets/MIDI Effects/Max MIDI Effect/CL MIDI Console Monitor", source)
        self.assertIn("Application Support/CL MIDI Console/Network Tools", source)
        self.assertIn("Applications/CL MIDI Network Assistant.app", source)
        self.assertIn('midi-console)', source)
        self.assertNotIn("pkill", source)

    def test_complete_release_contains_device_assistant_and_native_tools(self):
        source = (ROOT / "scripts" / "build_release.sh").read_text()
        for required in (
            "Max for Live à installer/CL MIDI Console Monitor",
            "CL MIDI Network Assistant.app",
            "CL MIDI Network Tools",
            "CLMIDINetworkGuardian",
            "CLMIDIRoundTripTester",
            "CLYamahaConsoleSimulator",
            "CLYamahaSimulatorDashboard",
            "CLMIDINetworkDashboard",
            "connect_rtp_peer.applescript",
            "list_rtp_peers.applescript",
            "open_rtp_settings.applescript",
        ):
            self.assertIn(required, source)

        export_source = (ROOT / "scripts" / "export_transport_kit.command").read_text()
        self.assertIn("CL MIDI Console Monitor.amxd", export_source)
        self.assertIn("CL MIDI Network Assistant.app/", export_source)
        self.assertIn("CLMIDIRoundTripTester", export_source)

    def test_network_assistant_bundles_its_macos_icon(self):
        for relative_path in (
            "scripts/build_release.sh",
            "scripts/build_midi_console_package.sh",
        ):
            source = (ROOT / relative_path).read_text()
            self.assertIn("CL_MIDI_Network_Assistant.icns", source)
            self.assertIn("paradis_latin_logo.jpg", source)
            self.assertIn("CFBundleIconFile", source)
            self.assertIn("NSHighResolutionCapable", source)
            self.assertIn("NSAppleEventsUsageDescription", source)
            self.assertIn('codesign --force --deep --sign -', source)
            self.assertIn('xattr -cr', source)

    def test_network_assistant_uses_the_native_dashboard(self):
        for relative_path in (
            "scripts/build_release.sh",
            "scripts/build_midi_console_package.sh",
        ):
            source = (ROOT / relative_path).read_text()
            self.assertIn("CLMIDINetworkDashboard", source)
            self.assertIn("Contents/MacOS/CL MIDI Network Assistant", source)
            self.assertIn("Contents/Resources/LegacyAssistant.sh", source)


if __name__ == "__main__":
    unittest.main()
