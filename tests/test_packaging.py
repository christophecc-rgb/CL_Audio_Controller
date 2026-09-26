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
        self.assertIn("('console_title_library.py', '.')", spec)

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

    def test_native_remote_supports_arrangement_confirmation_dialog(self):
        source = (PROJECT_ROOT / "packaging/RemoteAbleton.m").read_text(encoding="utf-8")
        self.assertIn("WKUIDelegate", source)
        self.assertIn("self.webView.UIDelegate = self", source)
        self.assertIn("runJavaScriptConfirmPanelWithMessage", source)
        self.assertIn('addButtonWithTitle:@"Continuer"', source)
        self.assertIn("completionHandler(response == NSAlertFirstButtonReturn)", source)

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

        self.assertIn("CL Show Control.app", script)
        self.assertIn("CL Arrangement Builder.app", script)
        self.assertIn("CL_Arrangement_Builder_Live", script)
        self.assertIn("AbletonOSC", script)
        self.assertIn("Max Audio Effect/CL Audio Controller", script)
        self.assertIn("trash_existing", script)
        self.assertIn('TRASH_ROOT="${CL_SUITE_TRASH_DIR:-$INSTALL_HOME/.Trash}"', script)
        self.assertIn('for legacy_backup in "${target}.sauvegarde_"*', script)
        self.assertIn('mv "$target" "$destination"', script)
        self.assertIn("prepare_controller_replacement", script)
        self.assertIn('tell application id "com.claudio.controller" to quit', script)
        self.assertIn("http://127.0.0.1:5055/quit", script)

        self.assertIn('local quit_requested=0', script)
        self.assertIn('if [[ "$quit_requested" != 1 ]]', script)
        self.assertIn("Serveur orphelin détecté", script)
        self.assertIn('open -gj "$controller_app"', script)
        self.assertIn("port_listening 5050", script)
        self.assertIn("port_listening 5055", script)
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
        self.assertIn("CL MIDI RTP Agent.app", script)
        self.assertNotIn("CL MIDI RTP Simulator.app", script)
        self.assertIn('RTP_AGENT_EXEC="$MIDI_NETWORK_APPS/CL MIDI RTP Agent.app/Contents/MacOS/CL MIDI RTP Agent"', script)
        self.assertIn("prepare_rtp_agent_replacement", script)
        self.assertIn("l’état réel (processus + LaunchAgent) fait foi", script)
        self.assertIn("pgrep -f -x", script)
        self.assertIn("com.claudio.midi-rtp-agent.plist", script)
        self.assertNotIn("com.claudio.midi-network-monitor.plist", script)
        self.assertNotIn("--background-monitor", script)
        self.assertIn("INSTALL_MIDI_RECEIVER", script)
        self.assertIn("detect_live", script)
        self.assertIn("resolve_user_library", script)
        self.assertIn("verify_copy", script)
        self.assertIn('COMPONENTS_ROOT="$SCRIPT_DIR/Composants"', script)
        self.assertNotIn("sudo", script)
        self.assertIn("pkill", script)

    def test_red_window_button_triggers_a_full_launcher_shutdown(self):
        launcher = (PROJECT_ROOT / "launcher_control.py").read_text(encoding="utf-8")
        self.assertIn("panel_window.events.closing += quit_when_main_panel_closes", launcher)
        self.assertIn("panel_window.events.closed += quit_when_main_panel_closes", launcher)
        self.assertIn("Fenêtre principale fermée — arrêt complet", launcher)
        self.assertIn('[str(executable), "--show-control-monitor"]', launcher)
        self.assertNotIn('[str(executable), "--background-monitor"]', launcher)
        self.assertIn("stop_midi_console_monitor()", launcher)

    def test_desktop_export_includes_full_suite_installer(self):
        script = (
            PROJECT_ROOT / "scripts/export_transport_kit.command"
        ).read_text(encoding="utf-8")

        self.assertIn("Installer la Suite CL.app", script)
        self.assertIn("Désinstaller la Suite CL.app", script)
        self.assertIn("Paradis Latin AutoScene - Live 10.amxd", script)
        self.assertIn("Paradis Latin AutoScene - Live 10.maxpat", script)
        self.assertIn("CL Arrangement Builder.app/", script)
        self.assertIn('"CL MIDI RTP Agent.app/"', script)
        self.assertNotIn('"CL MIDI RTP Simulator.app/"', script)
        self.assertIn("CFBundleIconFile", script)
        self.assertIn("CL_RELEASE_OUTPUT_ROOT", script)
        self.assertIn("CL_RELEASE_SKIP_DMG=1", script)
        self.assertNotIn('require_file "$CONTROLLER_RELEASE/CL_Audio_Controller_${VERSION}.dmg"', script)
        self.assertIn("CLSuiteInstallerApp.m", script)
        self.assertIn("installer-universal", script)
        self.assertIn("x86_64-apple-macosx10.15", script)
        self.assertIn("arm64-apple-macosx10.15", script)
        self.assertIn('"$CL_PYTHON" -m PyInstaller', script)
        self.assertIn('"Arrangement Builder Live.spec"', script)
        self.assertIn('ditto "$BUILDER_APP"', script)
        self.assertIn('ditto "$BUILDER_DIR/RemoteScript"', script)
        self.assertNotIn('BUILDER_DIR/release/Arrangement Builder Live 1.2.2', script)

    def test_transport_export_does_not_depend_on_dmg_creation(self):
        release = (PROJECT_ROOT / "scripts/build_release.sh").read_text(encoding="utf-8")
        self.assertIn('SKIP_DMG="${CL_RELEASE_SKIP_DMG:-0}"', release)
        self.assertIn('"$SKIP_DMG" != "1"', release)
        self.assertIn('checksum_files=("$ZIP_NAME" "$M4L_ZIP_NAME")', release)

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
        self.assertIn("Mac Télécommande", source)
        self.assertIn("CL Arrangement Builder", source)
        self.assertIn("Paradis Latin AutoScene", source)
        self.assertIn("CL MIDI Network Manager + simulateur", source)
        self.assertIn("Mac Ableton Lecteur", source)
        self.assertIn("Simulateur console", source)
        self.assertIn("agent RTP léger", source)
        self.assertIn("roleChanged:", source)
        self.assertIn("Installer_Toute_La_Suite_CL.command", source)
        self.assertIn("Desinstaller_La_Suite_CL.command", source)
        self.assertIn("CL_SUITE_COMPONENTS", source)
        self.assertIn("CL_SUITE_UNINSTALL_COMPONENTS", source)
        self.assertIn("NSProgressIndicatorStyleBar", source)
        self.assertIn("Installation terminée", source)
        self.assertIn('@"ParadisLatin.jpg"', source)
        self.assertIn('buttonWithTitle:@"Quitter"', source)
        self.assertIn('quit.keyEquivalent = @"\\033"', source)
        self.assertIn("failureMessageForLog", source)
        self.assertIn('@"ERREUR : "', source)
        installer_section = source.split("] : @[", 1)[1]
        self.assertLess(installer_section.index("Paradis Latin AutoScene"), installer_section.index("Mac Télécommande"))
        self.assertLess(installer_section.index("Mac Télécommande"), installer_section.index("CL Arrangement Builder"))
        self.assertLess(installer_section.index("CL Arrangement Builder"), installer_section.index("CL MIDI Network Manager + simulateur"))
        self.assertIn('@selector(terminate:)', source)
        self.assertIn('keyEquivalent:@"q"', source)

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
                "Applications/CL Show Control.app",
                "Applications/CL ShowCue.app",
                "Applications/CL Cue Editor.app",
                "CL_Transport",
                "Applications/CL Arrangement Builder.app",
                "Applications/CL MIDI Network Manager.app",
                "Ableton Live 11-12/Remote Scripts/AbletonOSC",
                "Ableton Live 11-12/Remote Scripts/CL_Arrangement_Builder_Live",
                "Ableton Live 11-12/Max for Live/CL Audio Controller - Remote",
                "Ableton Live 11-12/Max for Live/CL Absolute MTC",
                "Ableton Live 11-12/Max for Live/Paradis Latin AutoScene",
                "Ableton Live 11-12/Max for Live/CL MIDI Console Monitor",
                "Outils_reseau_MIDI",
            )
            for relative in required_directories:
                directory = components / relative
                directory.mkdir(parents=True)
                (directory / "payload.txt").write_text(relative)

            fake_live = home / "Applications/Ableton Live 12 Suite.app"
            fake_live.mkdir(parents=True)

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
                    "CL_SUITE_LIVE_APPS": str(fake_live),
                    "CL_SUITE_ASSUME_M4L": "1",
                }
            )
            subprocess.run([str(engine)], check=True, env=environment, capture_output=True)

            self.assertTrue((home / "Applications/CL Show Control.app").is_dir())
            self.assertTrue((home / "Applications/Prod Ableton/CL Arrangement Builder.app").is_dir())
            self.assertTrue((home / "Applications/Analyse - Réseau - MIDI/CL MIDI Network Manager.app").is_dir())

            legacy = home / "Applications/CL Show Control.app.sauvegarde_ancienne"
            legacy.mkdir()
            subprocess.run([str(engine)], check=True, env=environment, capture_output=True)
            trash_sessions = list((home / ".Trash").glob("CL Suite remplacée *"))
            self.assertTrue(trash_sessions)
            trashed_names = {item.name for session in trash_sessions for item in session.iterdir()}
            self.assertTrue(any(name.endswith("CL Show Control.app") for name in trashed_names))
            self.assertTrue(any("sauvegarde_ancienne" in name for name in trashed_names))
            self.assertTrue(
                (home / "Music/Ableton/User Library/Remote Scripts/AbletonOSC").is_dir()
            )
            manifest = home / "Library/Application Support/CL Audio Controller/CL_Suite_install_manifest.tsv"
            self.assertTrue(manifest.is_file())
            self.assertEqual(len(manifest.read_text().splitlines()), 12)


if __name__ == "__main__":
    unittest.main()
