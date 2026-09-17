import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ConfigurationCheckerPackagingTests(unittest.TestCase):
    def test_bundle_identity_and_version_are_canonical(self):
        script = (ROOT / "scripts" / "build_configuration_checker_app.sh").read_text()
        self.assertIn('APP_NAME="CL MIDI & RTP Diagnostic"', script)
        self.assertIn('PLIST_APP_NAME="CL MIDI &amp; RTP Diagnostic"', script)
        self.assertIn('BUNDLE_ID="com.claudio.configurationchecker"', script)
        self.assertIn('VERSION="${1:-0.1.0}"', script)
        self.assertIn('paradis_latin_logo.jpg', script)
        self.assertNotIn("Cel Audio", script)

    def test_packaging_does_not_install_or_change_functional_sources(self):
        script = (ROOT / "scripts" / "build_configuration_checker_app.sh").read_text()
        self.assertIn('dist/configuration-checker', script)
        self.assertNotIn('/Applications/', script)
        self.assertNotIn('$HOME/Applications', script)
        self.assertNotIn('~/Applications', script)

    def test_icon_is_reproducible_and_distinct(self):
        script = (ROOT / "scripts" / "generate_configuration_checker_icon.sh").read_text()
        generator = (ROOT / "packaging" / "configuration_checker" / "generate_icon.swift").read_text()
        self.assertIn('CL_MIDI_RTP_Diagnostic.png', script)
        self.assertIn('iconutil -c icns', script)
        self.assertIn('CONFIG CHECK', generator)
        self.assertIn('verification badge', generator)


if __name__ == "__main__":
    unittest.main()
