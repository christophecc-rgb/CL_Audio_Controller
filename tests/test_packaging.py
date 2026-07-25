import pathlib
import unittest


PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[1]


class PackagingTests(unittest.TestCase):
    def test_bundle_does_not_duplicate_the_max_for_live_source_tree(self):
        spec = (PROJECT_ROOT / "CL Audio Controller.spec").read_text(encoding="utf-8")

        self.assertNotIn("('M4L', 'M4L')", spec)
        self.assertIn("'CFBundleShortVersionString': '2.2.0'", spec)
        self.assertIn("'CFBundleVersion': '6'", spec)

    def test_release_contains_offline_dependencies_and_clear_installation_files(self):
        script = (PROJECT_ROOT / "scripts/build_release.sh").read_text(encoding="utf-8")

        self.assertIn('VERSION="${1:-2.2.0}"', script)
        self.assertIn("AbletonOSC CL/AbletonOSC", script)
        self.assertIn("Max for Live à installer", script)
        self.assertIn("Installer_CL_Audio_Controller.command", script)
        self.assertIn("LISEZ_MOI_INSTALLATION.txt", script)
        self.assertIn("CONTENU_SHA256.txt", script)
        self.assertIn("git -C \"$ABLETONOSC_ROOT\" archive", script)
        self.assertNotIn("github.com/ideoforms", script)

    def test_user_installer_is_non_destructive_and_needs_no_administrator(self):
        script = (
            PROJECT_ROOT / "packaging/Installer_CL_Audio_Controller.command"
        ).read_text(encoding="utf-8")

        self.assertIn('USER_APPS="$HOME/Applications"', script)
        self.assertIn("backup_existing", script)
        self.assertIn('mv "$target" "$backup"', script)
        self.assertNotIn("sudo", script)
        self.assertNotIn("rm -rf", script)
        self.assertNotIn("pkill", script)

    def test_new_mac_guide_documents_runtime_dependencies_and_live_10_limit(self):
        guide = (
            PROJECT_ROOT / "packaging/INSTALLATION_NOUVEAU_MAC.txt"
        ).read_text(encoding="utf-8")

        self.assertIn("aucune installation Python", guide)
        self.assertIn("AbletonOSC CL", guide)
        self.assertIn("Max for Live", guide)
        self.assertIn("Ableton Live 10", guide)
        self.assertIn("clic droit > Ouvrir", guide)


if __name__ == "__main__":
    unittest.main()
