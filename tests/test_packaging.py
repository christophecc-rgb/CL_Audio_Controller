import pathlib
import hashlib
import os
import shutil
import subprocess
import tempfile
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

    def test_full_suite_installer_covers_apps_and_ableton_components(self):
        script = (
            PROJECT_ROOT / "packaging/Installer_Toute_La_Suite_CL.command"
        ).read_text(encoding="utf-8")

        self.assertIn("CL Audio Controller.app", script)
        self.assertIn("Arrangement Builder Live.app", script)
        self.assertIn("CL_Arrangement_Builder_Live", script)
        self.assertIn("AbletonOSC", script)
        self.assertIn("Max Audio Effect/CL Audio Controller", script)
        self.assertIn("backup_existing", script)
        self.assertIn("Live 10", script)
        self.assertIn("Live 11", script)
        self.assertIn("CL Audio Controller - Live 10", script)
        self.assertIn("CL Audio Controller - Remote", script)
        self.assertIn("CL Audio Controller - AutoScene", script)
        self.assertIn("Télécommande CL Audio uniquement", script)
        self.assertIn("Arrangement Builder uniquement", script)
        self.assertIn("AutoScene uniquement", script)
        self.assertIn("CL_SUITE_COMPONENTS", script)
        self.assertIn("Ableton Live 10", script)
        self.assertIn("Paradis Latin AutoScene - Live 10", script)
        self.assertIn('COMPONENTS_ROOT="$SCRIPT_DIR/Composants"', script)
        self.assertNotIn("sudo", script)
        self.assertNotIn("pkill", script)

    def test_desktop_export_includes_full_suite_installer(self):
        script = (
            PROJECT_ROOT / "scripts/export_transport_kit.command"
        ).read_text(encoding="utf-8")

        self.assertIn("Installer la Suite CL.app", script)
        self.assertIn("Désinstaller la Suite CL.app", script)
        self.assertIn("Paradis Latin AutoScene - Live 10.amxd", script)
        self.assertIn("Paradis Latin AutoScene - Live 10.maxpat", script)
        self.assertIn("Arrangement Builder Live.app/", script)
        self.assertIn("CFBundleIconFile", script)
        self.assertIn("CL_RELEASE_OUTPUT_ROOT", script)
        self.assertIn("CLSuiteInstallerApp.m", script)
        self.assertIn("installer-universal", script)
        self.assertIn("x86_64-apple-macosx10.15", script)
        self.assertIn("arm64-apple-macosx10.15", script)

    def test_graphical_installer_wraps_the_noninteractive_engine(self):
        source = (
            PROJECT_ROOT / "packaging" / "Installer_La_Suite_CL.app.sh"
        ).read_text(encoding="utf-8")
        self.assertIn("choose from list", source)
        self.assertIn("with multiple selections allowed", source)
        self.assertIn("CL_SUITE_NONINTERACTIVE=1", source)
        self.assertIn('CL_SUITE_LIVE_FAMILY="$live_family"', source)
        self.assertNotIn("sudo", source)

    def test_graphical_packaging_launchers_have_valid_macos_bash_syntax(self):
        launchers = (
            "Installer_La_Suite_CL.app.sh",
            "Desinstaller_La_Suite_CL.app.sh",
            "Creer_Le_Kit_CL.app.sh",
        )
        for launcher in launchers:
            with self.subTest(launcher=launcher):
                subprocess.run(
                    ["/bin/bash", "-n", str(PROJECT_ROOT / "packaging" / launcher)],
                    check=True,
                    capture_output=True,
                    text=True,
                )

    def test_native_installer_has_branded_component_cards_and_keeps_the_existing_engines(self):
        source = (PROJECT_ROOT / "packaging" / "CLSuiteInstallerApp.m").read_text(encoding="utf-8")
        self.assertIn("CL Audio Controller", source)
        self.assertIn("CL Arrangement Builder Live", source)
        self.assertIn("Paradis Latin AutoScene", source)
        self.assertIn("CL MIDI Console Monitor", source)
        self.assertIn("Installer_Toute_La_Suite_CL.command", source)
        self.assertIn("Desinstaller_La_Suite_CL.command", source)
        self.assertIn("CL_SUITE_COMPONENTS", source)
        self.assertIn("CL_SUITE_UNINSTALL_COMPONENTS", source)
        self.assertIn("NSProgressIndicatorStyleBar", source)
        self.assertIn("Installation terminée", source)
        installer_section = source.split("] : @[", 1)[1]
        self.assertLess(installer_section.index("Paradis Latin AutoScene"), installer_section.index("CL Audio Controller"))
        self.assertLess(installer_section.index("CL Audio Controller"), installer_section.index("CL Arrangement Builder Live"))
        self.assertLess(installer_section.index("CL Arrangement Builder Live"), installer_section.index("CL MIDI Console Monitor"))

    def test_desktop_kit_builder_is_a_macos_app_with_the_cl_icon(self):
        wrapper = (
            PROJECT_ROOT / "packaging" / "Creer_Le_Kit_CL.app.sh"
        ).read_text(encoding="utf-8")
        builder = (
            PROJECT_ROOT / "scripts" / "install_desktop_kit_builder.sh"
        ).read_text(encoding="utf-8")
        self.assertIn("export_transport_kit.command", wrapper)
        self.assertIn("display dialog", wrapper)
        self.assertIn("Bureau uniquement", wrapper)
        self.assertIn("Bureau + iCloud Drive", wrapper)
        self.assertIn("Bureau + AirDrop", wrapper)
        self.assertIn("Installer directement sur ce Mac", wrapper)
        self.assertIn("CL_SUITE_EXPORT_DIR", wrapper)
        self.assertIn("CL_SUITE_REVEAL_OUTPUT=0", wrapper)
        self.assertIn('open -W "$installer_app"', wrapper)
        self.assertIn('Installer la Suite CL.app', wrapper)
        self.assertIn("NSSharingServiceNameSendViaAirDrop", wrapper)
        self.assertIn("service.performWithItems([fileURL])", wrapper)
        self.assertIn('osascript -l JavaScript - "$latest_zip"', wrapper)
        self.assertIn("CL_SUITE_SKIP_ICLOUD=1", wrapper)
        self.assertIn('terminal_command="/bin/bash $quoted_builder', wrapper)
        self.assertIn('tell application "Terminal"', wrapper)
        self.assertIn('while [[ ! -f "$STATUS_FILE" ]]', wrapper)
        self.assertIn("grep -E '^/.*/CL_Suite_Transport_", wrapper)
        self.assertIn("CL_AUDIO.icns", builder)
        self.assertIn("CFBundleIconFile", builder)
        self.assertIn("Créer le Kit CL.app", builder)
        self.assertNotIn("sudo", wrapper + builder)

    def test_live_12_complete_install_uses_the_canonical_payload(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            kit = root / "kit"
            home = root / "home"
            engine = kit / "Installer_Toute_La_Suite_CL.command"
            kit.mkdir()
            shutil.copy2(
                PROJECT_ROOT / "packaging" / "Installer_Toute_La_Suite_CL.command",
                engine,
            )
            engine.chmod(0o755)

            components = kit / "Composants"
            required_directories = (
                "Applications/CL Audio Controller.app",
                "Applications/Arrangement Builder Live.app",
                "Applications/CL MIDI Network Assistant.app",
                "Ableton Live 11-12/Remote Scripts/AbletonOSC",
                "Ableton Live 11-12/Remote Scripts/CL_Arrangement_Builder_Live",
                "Ableton Live 11-12/Max for Live/CL Audio Controller - Remote",
                "Ableton Live 11-12/Max for Live/Paradis Latin AutoScene",
                "Ableton Live 11-12/Max for Live/CL MIDI Console Monitor",
                "Outils réseau MIDI",
            )
            for relative in required_directories:
                directory = components / relative
                directory.mkdir(parents=True)
                (directory / "payload.txt").write_text(relative)

            manifest_lines = []
            for payload in sorted(components.rglob("payload.txt")):
                digest = hashlib.sha256(payload.read_bytes()).hexdigest()
                manifest_lines.append(f"{digest}  {payload.relative_to(kit)}")
            (kit / "COMPONENTS_SHA256.txt").write_text(
                "\n".join(manifest_lines) + "\n"
            )

            environment = os.environ.copy()
            environment.update(
                {
                    "CL_SUITE_NONINTERACTIVE": "1",
                    "CL_SUITE_LIVE_FAMILY": "12",
                    "CL_SUITE_COMPONENTS": "remote,builder,autoscene,midi-console",
                    "CL_SUITE_INSTALL_HOME": str(home),
                }
            )
            subprocess.run([str(engine)], check=True, env=environment, capture_output=True)

            self.assertTrue((home / "Applications/CL Audio Controller.app").is_dir())
            self.assertTrue((home / "Applications/Arrangement Builder Live.app").is_dir())
            self.assertTrue((home / "Applications/CL MIDI Network Assistant.app").is_dir())
            self.assertTrue(
                (home / "Music/Ableton/User Library/Remote Scripts/AbletonOSC").is_dir()
            )
            manifest = home / "Library/Application Support/CL Audio Controller/CL_Suite_install_manifest.tsv"
            self.assertTrue(manifest.is_file())
            self.assertEqual(len(manifest.read_text().splitlines()), 9)


if __name__ == "__main__":
    unittest.main()
