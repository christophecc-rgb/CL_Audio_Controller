# Nettoyage conservateur du dépôt — 7 octobre 2026

Branche : `feature/ableton-mtc-bridge`. Aucun commit, push, reset, stash ou changement de branche.

Sauvegarde ciblée : `/private/tmp/CL_REPO_CLEANUP_20261007_034748` (également accessible par `/tmp/CL_REPO_CLEANUP_20261007_034748`).

## Résultat

- 262 fichiers archivés, vérifiés par SHA-256, puis retirés (5999108 octets).
- 10 fichiers : Finder.
- 246 fichiers : bytecode.
- 5 fichiers : pytest metadata/state.
- 1 fichiers : template backup.
- 10 répertoires de cache vides retirés individuellement.
- Aucun déplacement direct : copies vérifiées avant retrait. La copie de template datée est archivée hors du dépôt.
- `.gitignore` : ajout unique de `*.bak-[0-9]*`, pour les sauvegardes datées. Sa version précédente est sauvegardée.
- Les 44 autres fichiers non suivis initiaux sont conservés ; audit individuel et références dans `untracked-audit.json`.
- Les 25 fichiers initialement modifiés sont inchangés par ce nettoyage.
- Releases, environnement Python, vendor, builds locaux, devices AMXD, bibliothèques CSV/CLF/RTP, configuration et sécurité restent conservés.
- Les trois gros AMXD suivis sont des fichiers de distribution référencés : ils ne sont pas des déchets.

## Classification

A — garder : chantiers récents, docs, captures de validation, tests, assets, sources et livrables utiles.
B — retrait appliqué : bytecode avec source existante, caches pytest standard, métadonnées Finder et ancien template daté non référencé.
C — ajout à gitignore : sauvegardes `.bak-<date>`. Les autres caches/livrables étaient déjà ignorés ; aucun fichier généré de ces types n’est suivi.
D — conserver, à confirmer :

- `tools/ableton_mtc_bridge/CLSyncProbe.m.before-clsync-v1` : Sauvegarde de source MTC distincte de la version active ; historique utile potentiel.
- `tools/ableton_mtc_bridge/CLAbletonMTCBridge.m.before-clsync-v1` : Sauvegarde de source MTC distincte de la version active ; historique utile potentiel.
- `build/bonjour-test` : Ancien dossier de construction local : utilité historique non déterminée, conservé.
- `build/pyinstaller-cache` : Ancien dossier de construction local : utilité historique non déterminée, conservé.
- `build/showcue-phase-test` : Ancien dossier de construction local : utilité historique non déterminée, conservé.
- `build/showcue-ui-final` : Ancien dossier de construction local : utilité historique non déterminée, conservé.
- `build/showcue-ui-test` : Ancien dossier de construction local : utilité historique non déterminée, conservé.

## Vérifications

- Python, exécution initiale : 426 réussis, 10 échecs, 1 ignoré. Neuf échecs provenaient de tentatives d’écriture du journal de sécurité réel bloquées par le sandbox ; un du test réseau local.
- Python, exécution isolée (`CL_SECURITY_DIRECTORY` dans la sauvegarde, port UDP temporaire sur loopback) : **436 réussis, 1 ignoré, 59 subtests réussis**.
- JavaScript : **18 suites réussies, 8 en échec**. Les quatre tests navigateur ont aussi été relancés avec Playwright et Chrome dans un profil temporaire ; les échecs sont désormais détaillés, sans dépendance manquante.
- Syntaxe : **248 fichiers Python, JavaScript et shell contrôlés, aucune erreur**.
- `git diff --check` : réussi.
- Vérification des empreintes : aucun fichier de travail protégé ni donnée de production contrôlée modifié.
- Tests exécutés sans régénération du bytecode ni du cache pytest. Aucune correction métier appliquée pour faire passer les tests.

### Suites JavaScript en échec

- `tests/js/test_ableton_discovery.cjs` : evalmachine.<anonymous>:22 /   el('clServerMode').querySelector('[value=local]').textContent=localBonjourName; /                      ^ /  / TypeError: el(...).querySelector is not a function
- `tests/js/test_console_health.cjs` : node:internal/assert/utils:146 /   throw error; /   ^ /  / AssertionError [ERR_ASSERTION]: Expected values to be strictly equal:
- `tests/js/test_console_health_ui.cjs` : AssertionError [ERR_ASSERTION]: The input did not match the regular expression /PC 13.*Scène 14/. Input: /  / 'CL5\n' + /   '○ Simulateur arrêté\n' + /   'Arrêté\n' +
- `tests/js/test_hot_backup_buttons.cjs` : AssertionError [ERR_ASSERTION]: Expected values to be strictly deep-equal: / + actual - expected /  /   { / +   bonjour_name: '192.168.1.138',
- `tests/js/test_network_target_independence.cjs` : evalmachine.<anonymous>:10 /   el('remoteAddress').textContent=bonjourShareURL(s.lan_url||'—'); /   ^ /  / ReferenceError: bonjourShareURL is not defined
- `tests/js/test_paradis_network.cjs` : page.waitForFunction: Timeout 30000ms exceeded. /     at /Users/mbprochris/Documents/GitHub/CL_Audio_Controller/tests/js/test_paradis_network.cjs:16:57 { /   log: [], /   name: 'TimeoutError' / }
- `tests/js/test_remote_design_system.cjs` : Traceback (most recent call last): /   File "/Users/mbprochris/Documents/GitHub/CL_Audio_Controller/tests/js/render_remote_fixture.py", line 13, in <module> /     Q.path=route;p=s/'templates'/f'{file}.html';p=p if p.exists() else r/'templates'/f'{file}.html';results[route]=n['decorate_remote_page_html'](R(p.read_text())).t /                                                                                                                    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^ /   File "decoration", line 642, in decorate_remote_page_html
- `tests/js/test_session_skins.cjs` : Traceback (most recent call last): /   File "/Users/mbprochris/Documents/GitHub/CL_Audio_Controller/tests/js/render_remote_fixture.py", line 13, in <module> /     Q.path=route;p=s/'templates'/f'{file}.html';p=p if p.exists() else r/'templates'/f'{file}.html';results[route]=n['decorate_remote_page_html'](R(p.read_text())).t /                                                                                                                    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^ /   File "decoration", line 642, in decorate_remote_page_html

## Audit individuel des fichiers non suivis initiaux

- **A** `backup_preferences.py` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `docs/BUILDER_IMPORT_COMPATIBILITY.md` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `docs/BUILDER_UI_REDESIGN.md` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `docs/PERFORMANCE_REPORT.md` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `docs/SHOWCUE_MOBILE_EDITOR.md` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `docs/SHOWCUE_PERMISSIONS.md` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `docs/builder-ui/after-1280.png` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : `docs/BUILDER_UI_REDESIGN.md`.
- **A** `docs/builder-ui/after-1512.png` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : `docs/BUILDER_UI_REDESIGN.md`.
- **A** `docs/builder-ui/batch-1512.png` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : `docs/BUILDER_UI_REDESIGN.md`.
- **A** `docs/builder-ui/before-1512.png` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : `docs/BUILDER_UI_REDESIGN.md`.
- **A** `docs/builder-ui/metrics.json` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `docs/builder-ui/remote-1512.png` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : `docs/BUILDER_UI_REDESIGN.md`.
- **A** `docs/builder-ui/sessions.png` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : `docs/BUILDER_UI_REDESIGN.md`.
- **A** `packaging/Installer_CL_Autonome.command` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : `scripts/package_autonomous.py`.
- **A** `scripts/package_autonomous.py` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `static/marquee/marquee_off.png` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : `static/marquee/showcue-marquee.css`.
- **A** `static/marquee/marquee_on.png` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : `static/marquee/showcue-marquee.css`.
- **A** `static/marquee/showcue-marquee.css` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `static/showcue-builder-access.js` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : `docs/BUILDER_UI_REDESIGN.md`, `tests/js/test_showcue_builder_access.cjs`, `templates/showcue_builder.html`, `tests/js/test_showcue_builder_layout.cjs`.
- **A** `static/showcue-builder-layout.css` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : `docs/BUILDER_UI_REDESIGN.md`, `templates/showcue_builder.html`.
- **A** `static/showcue-builder-layout.js` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : `docs/BUILDER_UI_REDESIGN.md`, `tests/js/test_showcue_builder_layout.cjs`, `templates/showcue_builder.html`.
- **A** `static/showcue-import-feedback.js` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : `templates/showcue_builder.html`, `tests/js/test_showcue_import_feedback.cjs`.
- **A** `static/showcue-mobile-editor.css` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : `templates/show_info.html`, `docs/SHOWCUE_MOBILE_EDITOR.md`, `tests/js/test_showcue_mobile_editor.cjs`.
- **A** `static/showcue-mobile-editor.js` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : `docs/SHOWCUE_MOBILE_EDITOR.md`, `tests/js/test_showcue_mobile_editor.cjs`, `templates/show_info.html`.
- **A** `static/showcue-phase-order.js` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : `docs/BUILDER_UI_REDESIGN.md`, `templates/showcue_builder.html`, `tests/js/test_showcue_builder_phase_order.cjs`.
- **B** `templates/show_info.html.bak-20261006-192713` — Copie datée du template, non référencée ; version active distincte conservée, snapshot archivé avant retrait. Références : aucune référence textuelle directe (conservé si utile).
- **A** `tests/js/test_remote_auth_showcue.cjs` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : `docs/SHOWCUE_MOBILE_EDITOR.md`.
- **A** `tests/js/test_remote_ltc_smoothing.cjs` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `tests/js/test_showcue_api_errors.cjs` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `tests/js/test_showcue_builder_access.cjs` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `tests/js/test_showcue_builder_layout.cjs` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : `docs/BUILDER_UI_REDESIGN.md`.
- **A** `tests/js/test_showcue_builder_phase_order.cjs` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `tests/js/test_showcue_import_feedback.cjs` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `tests/js/test_showcue_import_menu.cjs` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `tests/js/test_showcue_mobile_editor.cjs` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : `docs/SHOWCUE_MOBILE_EDITOR.md`.
- **A** `tests/js/test_showcue_phase_order.cjs` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `tests/test_autonomous_mode.py` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `tests/test_backup_preferences.py` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `tests/test_builder_batch_persistence.py` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : `docs/BUILDER_UI_REDESIGN.md`.
- **A** `tests/test_builder_import_compatibility.py` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `tests/test_builder_manual_order.py` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `tests/test_builder_preview_diagnostics.py` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `tests/test_builder_remote_readonly.py` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).
- **A** `tests/test_showcue_permissions.py` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : `docs/SHOWCUE_MOBILE_EDITOR.md`.
- **A** `tests/verify_performance_report.py` — Fonctionnalité récente, documentation ou test utile ; conservé même sans référence textuelle directe. Références : aucune référence textuelle directe (conservé si utile).

## Liste exacte des fichiers retirés

Chaque chemin ci-dessous est conservé à l’identique sous `files/` dans la sauvegarde. Le manifeste contient son SHA-256 et le motif du retrait.

- `.DS_Store`
- `packaging/__pycache__/role_install.cpython-314.pyc`
- `tools/.DS_Store`
- `tools/ableton_mtc_bridge/.DS_Store`
- `INSTALLER_AbletonOSC/__pycache__/cl_fast_poll.cpython-314.pyc`
- `INSTALLER_AbletonOSC/__pycache__/install_bonjour.cpython-314.pyc`
- `INSTALLER_AbletonOSC/__pycache__/cl_bonjour.cpython-314.pyc`
- `INSTALLER_AbletonOSC/__pycache__/install_fast_poll.cpython-314.pyc`
- `.pytest_cache/.DS_Store`
- `.pytest_cache/v/.DS_Store`
- `tests/.DS_Store`
- `tests/js/__pycache__/render_remote_fixture.cpython-314.pyc`
- `tests/__pycache__/test_builder_remote_readonly.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_cues.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_passive_scene_listeners.cpython-314.pyc`
- `tests/__pycache__/test_show_audio_runtime.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_medleys.cpython-314.pyc`
- `tests/__pycache__/test_permanent_devices.cpython-314.pyc`
- `tests/__pycache__/test_mtc_bridge_control.cpython-314.pyc`
- `tests/__pycache__/test_midi_monitor.cpython-314.pyc`
- `tests/__pycache__/test_show_cues.cpython-314.pyc`
- `tests/__pycache__/test_showcue_v1_import.cpython-314.pyc`
- `tests/__pycache__/test_show_audio_arrangement_resolver.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_builder.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_device_production_states.cpython-314.pyc`
- `tests/__pycache__/test_show_audio_ableton_offline.cpython-314.pyc`
- `tests/__pycache__/test_liobox_backup_preflight.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_export_plan.cpython-314.pyc`
- `tests/__pycache__/test_midi_console_monitor_v2.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_print_preflight.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_remote_passive_feedback.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_scene_parser.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_ableton.cpython-314.pyc`
- `tests/__pycache__/test_device_profiles.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_remote_passive_feedback.cpython-314.pyc`
- `tests/__pycache__/test_showcue_access.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_paradis_network.cpython-314.pyc`
- `tests/__pycache__/test_live_set_generation.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_launcher_cleanup.cpython-314.pyc`
- `tests/__pycache__/test_backup_scene_follow.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_osc_transport.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_scan.cpython-314.pyc`
- `tests/__pycache__/test_show_audio_http.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_midi_analyzer_app.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_app_icons.cpython-314.pyc`
- `tests/__pycache__/test_ltc_receiver.cpython-314.pyc`
- `tests/__pycache__/test_packaging.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_ableton_discovery.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_showcue_v1_import.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_midi_network_assistant.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_builder_desktop.cpython-314.pyc`
- `tests/__pycache__/test_mtc_bridge_control.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_showcue_builder.cpython-314.pyc`
- `tests/__pycache__/test_logic_bridge.cpython-314.pyc`
- `tests/__pycache__/test_local_simulator_lifecycle.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_server_identity.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_cl_transport.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_plan.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_ableton_bonjour_publisher.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_builder_batch_persistence.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_ableton_offline.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_configuration_checker_packaging.cpython-314.pyc`
- `tests/__pycache__/test_show_audio_batch_export.cpython-314.pyc`
- `tests/__pycache__/test_xfader_max_device.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_network_target_independence.cpython-314.pyc`
- `tests/__pycache__/test_midi_expected_bonjour_lifecycle.cpython-314.pyc`
- `tests/__pycache__/test_scene_backup_udp.cpython-314.pyc`
- `tests/__pycache__/test_midi_network_assistant.cpython-314.pyc`
- `tests/__pycache__/test_midi_console_monitor_v2.cpython-314.pyc`
- `tests/__pycache__/test_dynamic_console_libraries.cpython-314.pyc`
- `tests/__pycache__/test_permanent_devices.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_server_ownership.cpython-314.pyc`
- `tests/__pycache__/test_server_ownership.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_ableton_targets.cpython-314.pyc`
- `tests/__pycache__/test_show_audio_snapshot.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_osc_transport.cpython-314.pyc`
- `tests/__pycache__/test_phase2_security.cpython-314.pyc`
- `tests/__pycache__/test_live_set_generation.cpython-314.pyc`
- `tests/__pycache__/test_ltc_receiver.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_app_icons.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_macos_architectures.cpython-314.pyc`
- `tests/__pycache__/test_show_audio_builder.cpython-314.pyc`
- `tests/__pycache__/test_showcue_builder.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_ableton_bonjour_publisher.cpython-314.pyc`
- `tests/__pycache__/test_command_layer.cpython-314.pyc`
- `tests/__pycache__/test_configuration_checker.cpython-314.pyc`
- `tests/__pycache__/test_midi_console_packaging.cpython-314.pyc`
- `tests/__pycache__/test_macos_architectures.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_midi_console_packaging.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_showcue_pdf_import.cpython-314.pyc`
- `tests/__pycache__/test_phase2_roles.cpython-314.pyc`
- `tests/__pycache__/test_show_audio_ableton.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_midi_network_tools.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_showcue_pdf_import.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_builder_desktop.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_midi_event.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_midi_expected_bonjour_lifecycle.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_export_plan.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_midi_endpoint_names.cpython-314.pyc`
- `tests/__pycache__/test_arrangement_go_transaction.cpython-314.pyc`
- `tests/__pycache__/test_phase1_installation.cpython-314.pyc`
- `tests/__pycache__/test_builder_import_compatibility.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_midi_console_monitor.cpython-314.pyc`
- `tests/__pycache__/test_development_access.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_medleys.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_ableton_targets.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_security_panel_network.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_showcue_native_exports.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_plan.cpython-314.pyc`
- `tests/__pycache__/test_autonomous_mode.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_showcue_permissions.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_print_preflight.cpython-314.pyc`
- `tests/__pycache__/test_show_audio_snapshot.cpython-314.pyc`
- `tests/__pycache__/test_device_profiles.cpython-314.pyc`
- `tests/__pycache__/test_hot_backup_sync.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_midi_event.cpython-314.pyc`
- `tests/__pycache__/test_show_audio_arrangement_resolver.cpython-314.pyc`
- `tests/__pycache__/test_phase1_installation.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_phase2_backup.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_cl_transport.cpython-314.pyc`
- `tests/__pycache__/test_command_layer.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_export_settings.cpython-314.pyc`
- `tests/__pycache__/test_device_production_states.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_model.cpython-314.pyc`
- `tests/__pycache__/test_runtime_identity.cpython-314.pyc`
- `tests/__pycache__/test_builder_preview_diagnostics.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_launcher_cleanup.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_midi_console_monitor.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/security_test_helper.cpython-314.pyc`
- `tests/__pycache__/test_show_audio_model.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_print_engine.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_network_target_independence.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_xfader_max_device.cpython-314.pyc`
- `tests/__pycache__/test_showcue_portable_roundtrip.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_configuration_checker_packaging.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_local_simulator_lifecycle.cpython-314.pyc`
- `tests/__pycache__/test_app_identity.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_ltc_max_device.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_ableton_fast_poll.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_admin_unlock_session.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_crossfader_target.cpython-314.pyc`
- `tests/__pycache__/test_m4l_distribution.cpython-314.pyc`
- `tests/__pycache__/test_remote_tls_setup.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_runtime.cpython-314.pyc`
- `tests/__pycache__/test_crossfader_target.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_dynamic_console_libraries.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_m4l_distribution.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_ltc_max_device.cpython-314.pyc`
- `tests/__pycache__/test_builder_manual_order.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_scene_backup_udp.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_print_engine.cpython-314.pyc`
- `tests/__pycache__/test_app_identity.cpython-314.pyc`
- `tests/__pycache__/test_console_title_library.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_packaging.cpython-314.pyc`
- `tests/__pycache__/test_backup_preferences.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_batch_export.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_passive_scene_listeners.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_runtime_identity.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_paradis_network.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_showcue_session_restoration.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_showcue_session_restoration.cpython-314.pyc`
- `tests/__pycache__/test_show_audio_scan.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_arrangement_go_transaction.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_midi_endpoint_names.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_logic_bridge.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_hot_backup_sync.cpython-314.pyc`
- `tests/__pycache__/test_server_identity.cpython-314.pyc`
- `tests/__pycache__/test_simulator_dashboard_state.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_export_settings.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_midi_analyzer_app.cpython-314.pyc`
- `tests/__pycache__/test_phase2_backup.cpython-314.pyc`
- `tests/__pycache__/test_phase2_roles.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_midi_network_tools.cpython-314.pyc`
- `tests/__pycache__/test_midi_monitor.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_launcher_remote_arm.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_http.cpython-314.pyc`
- `tests/__pycache__/test_configuration_checker.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_show_audio_scene_parser.cpython-314.pyc`
- `tests/__pycache__/test_ableton_discovery.cpython-314.pyc`
- `tests/__pycache__/test_show_audio_playback_sources.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_console_title_library.cpython-314.pyc`
- `tests/__pycache__/test_show_audio_playback_sources.cpython-314.pyc`
- `tests/__pycache__/test_midi_network_assistant_resolution.cpython-314-pytest-9.1.1.pyc`
- `tests/__pycache__/test_phase2_security.cpython-314-pytest-9.1.1.pyc`
- `tests/manual/__pycache__/showcue_export_fixture.cpython-314.pyc`
- `__pycache__/show_audio_ableton.cpython-314.pyc`
- `__pycache__/show_audio_scene_parser.cpython-314.pyc`
- `__pycache__/show_audio_arrangement_resolver.cpython-314.pyc`
- `__pycache__/cl_transport.cpython-314.pyc`
- `__pycache__/show_audio_export_job.cpython-314.pyc`
- `__pycache__/showcue_desktop.cpython-314.pyc`
- `__pycache__/show_audio_print_engine.cpython-314.pyc`
- `__pycache__/bonjour_remote.cpython-314.pyc`
- `__pycache__/runtime_identity.cpython-314.pyc`
- `__pycache__/show_audio_model.cpython-314.pyc`
- `__pycache__/show_audio_medleys.cpython-314.pyc`
- `__pycache__/ableton_discovery.cpython-314.pyc`
- `__pycache__/hot_backup_sync.cpython-314.pyc`
- `__pycache__/show_audio_model_cli.cpython-314.pyc`
- `__pycache__/show_audio_group_scan.cpython-314.pyc`
- `__pycache__/show_audio_http.cpython-314.pyc`
- `__pycache__/scene_backup_receiver.cpython-314.pyc`
- `__pycache__/show_audio_export_plan.cpython-314.pyc`
- `__pycache__/remote_security.cpython-314.pyc`
- `__pycache__/show_audio_ableton_offline.cpython-314.pyc`
- `__pycache__/show_audio_snapshot_cli.cpython-314.pyc`
- `__pycache__/show_audio_plan.cpython-314.pyc`
- `__pycache__/show_audio_builder.cpython-314.pyc`
- `__pycache__/showcue_session_archive.cpython-314.pyc`
- `__pycache__/device_profiles.cpython-314.pyc`
- `__pycache__/backup_scene_follow.cpython-314.pyc`
- `__pycache__/show_audio_builder_desktop.cpython-314.pyc`
- `__pycache__/showcue_runtime_check.cpython-314.pyc`
- `__pycache__/osc_transport.cpython-314.pyc`
- `__pycache__/app.cpython-314.pyc`
- `__pycache__/ltc_receiver.cpython-314.pyc`
- `__pycache__/showcue_builder_desktop.cpython-314.pyc`
- `__pycache__/showcue_pdf_import.cpython-314.pyc`
- `__pycache__/ableton_targets.cpython-314.pyc`
- `__pycache__/show_audio_batch_export.cpython-314.pyc`
- `__pycache__/launcher_control.cpython-314.pyc`
- `__pycache__/midi_endpoint_names.cpython-314.pyc`
- `__pycache__/security_http.cpython-314.pyc`
- `__pycache__/show_cues.cpython-314.pyc`
- `__pycache__/show_audio_snapshot.cpython-314.pyc`
- `__pycache__/show_audio_playback_sources.cpython-314.pyc`
- `__pycache__/backup_preferences.cpython-314.pyc`
- `__pycache__/scene_backup_udp.cpython-314.pyc`
- `__pycache__/console_title_library.cpython-314.pyc`
- `__pycache__/remote_window.cpython-314.pyc`
- `__pycache__/show_audio_export_plan_cli.cpython-314.pyc`
- `__pycache__/show_audio_runtime.cpython-314.pyc`
- `__pycache__/show_audio_scan.cpython-314.pyc`
- `__pycache__/server_ownership.cpython-314.pyc`
- `__pycache__/scene_backup_protocol.cpython-314.pyc`
- `__pycache__/show_audio_export_settings.cpython-314.pyc`
- `__pycache__/build_identity.cpython-314.pyc`
- `__pycache__/security_recovery.cpython-314.pyc`
- `__pycache__/showcue_builder.cpython-314.pyc`
- `__pycache__/show_audio_http_scan.cpython-314.pyc`
- `__pycache__/show_audio_cli.cpython-314.pyc`
- `__pycache__/remote_tls.cpython-314.pyc`
- `docs/.DS_Store`
- `scripts/.DS_Store`
- `scripts/__pycache__/package_autonomous.cpython-314.pyc`
- `scripts/__pycache__/create_ltc_remote_device.cpython-314.pyc`
- `scripts/__pycache__/build_cl_transport.cpython-314.pyc`
- `scripts/__pycache__/generate_app_icon_variants.cpython-314.pyc`
- `scripts/__pycache__/build_xfader_device.cpython-314.pyc`
- `scripts/__pycache__/build_cl_audio_icon.cpython-314.pyc`
- `scripts/__pycache__/verify_app_identity.cpython-314.pyc`
- `scripts/__pycache__/create_midi_console_monitor_v2.cpython-314.pyc`
- `scripts/__pycache__/verify_macos_architectures.cpython-314.pyc`
- `scripts/__pycache__/create_midi_console_monitor.cpython-314.pyc`
- `M4L/.DS_Store`
- `assets/.DS_Store`
- `.pytest_cache/CACHEDIR.TAG`
- `.pytest_cache/README.md`
- `.pytest_cache/.gitignore`
- `.pytest_cache/v/cache/nodeids`
- `.pytest_cache/v/cache/lastfailed`
- `templates/show_info.html.bak-20261006-192713`

## Journaux et manifests

Inventaire complet, gros fichiers, références, statut initial/final et journaux de tests : `/private/tmp/CL_REPO_CLEANUP_20261007_034748`.
Les 3 389 artefacts recensés incluent les environnements et livrables conservés ; seuls les fichiers explicitement listés ci-dessus ont été retirés.
Aucun historique Git ou historique documentaire n’a été supprimé.

## Statut Git final

```text
 M .gitignore
 M app.py
 M launcher_control.py
 M osc_transport.py
 M remote_security.py
 M scripts/export_transport_kit.command
 M security_http.py
 M show_cues.py
 M showcue_builder.py
 M static/remote-auth.js
 M static/remote-v2.js
 M static/security-panel.html
 M static/security-panel.js
 M static/showcue-editor.css
 M static/showcue-editor.js
 M static/showcue-sessions.js
 M static/showcue-stage.css
 M static/showcue-stage.js
 M templates/show_info.html
 M templates/showcue_builder.html
 M tests/js/test_showcue_sessions.cjs
 M tests/test_live_set_generation.py
 M tests/test_osc_transport.py
 M tests/test_show_cues.py
 M tests/test_showcue_builder.py
 M tools/cl_midi_network/CLMIDIPerformanceMonitor.m
?? backup_preferences.py
?? docs/BUILDER_IMPORT_COMPATIBILITY.md
?? docs/BUILDER_UI_REDESIGN.md
?? docs/PERFORMANCE_REPORT.md
?? docs/REPO_CLEANUP_2026-10-07.md
?? docs/SHOWCUE_MOBILE_EDITOR.md
?? docs/SHOWCUE_PERMISSIONS.md
?? docs/builder-ui/
?? packaging/Installer_CL_Autonome.command
?? scripts/package_autonomous.py
?? static/marquee/
?? static/showcue-builder-access.js
?? static/showcue-builder-layout.css
?? static/showcue-builder-layout.js
?? static/showcue-import-feedback.js
?? static/showcue-mobile-editor.css
?? static/showcue-mobile-editor.js
?? static/showcue-phase-order.js
?? tests/js/test_remote_auth_showcue.cjs
?? tests/js/test_remote_ltc_smoothing.cjs
?? tests/js/test_showcue_api_errors.cjs
?? tests/js/test_showcue_builder_access.cjs
?? tests/js/test_showcue_builder_layout.cjs
?? tests/js/test_showcue_builder_phase_order.cjs
?? tests/js/test_showcue_import_feedback.cjs
?? tests/js/test_showcue_import_menu.cjs
?? tests/js/test_showcue_mobile_editor.cjs
?? tests/js/test_showcue_phase_order.cjs
?? tests/test_autonomous_mode.py
?? tests/test_backup_preferences.py
?? tests/test_builder_batch_persistence.py
?? tests/test_builder_import_compatibility.py
?? tests/test_builder_manual_order.py
?? tests/test_builder_preview_diagnostics.py
?? tests/test_builder_remote_readonly.py
?? tests/test_showcue_permissions.py
?? tests/verify_performance_report.py
```
