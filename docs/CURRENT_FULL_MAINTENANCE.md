# État de maintenance de la base FULL — 14 octobre 2026

Branche : `cleanup/current-full`, créée depuis `main` au commit
`ba0b163be66bb8fe575c1f8cfc6a57de36eeea0b`. Nettoyage normal dans de nouveaux
commits locaux ; aucun reset, réécriture, merge Light, build, installateur ou push.
Les références main, feature/local-light et origin/* restent inchangées.

## Classement de l'inventaire

A = nécessaire actuellement ; B = historique utile ; C = obsolète supprimé ;
D = ambigu conservé. L'âge ou la taille ne suffit pas à justifier une suppression.

| Ensemble examiné | Classe et décision |
| --- | --- |
| Sources Python, templates, static, tests et fixtures .showcue | A : conservés, aucune logique fonctionnelle modifiée. |
| packaging/, scripts/, INSTALLER_AbletonOSC/ | A : scripts actifs, outils autonomes et variantes avec références dans le packaging/tests. Aucune variante démontrée morte n'est supprimée. |
| resources/app_identity.json et bibliothèques consoles | A : noms, alias et données de production ; conservés. |
| CL_Transport/, sessions ShowCue et manifests actifs | A : données utiles ; aucune suppression ni modification. |
| M4L/Devices, M4L/Install et devices racine | A : sources/distribution/tests, 3 gros AMXD LTC conservés. |
| Icônes, logos, icon.iconset, PNG et AMXD | A/B/D : 71 ressources binaires suivies restantes, environ 69 Mo, conservées. Certaines images de maquettes n'ont pas de consommateur opérationnel attesté mais sont des références originales ambiguës. |
| CHANGELOG et anciennes versions 2.0/2.1 | B : historique de releases, pas des artefacts à effacer. |
| BUILD_ENVIRONMENT et licences | A/B : prérequis utiles, référence historique explicitée. |
| PHASE1/PHASE2, MIDI_RTP_NAMING, PERMANENT_DEVICES | A/B : lifecycle, compatibilité, rôles et sécurité spécifiques, pas de remplacement complet plus récent. |
| HOT_BACKUP_EVENT_SYNC_AUDIT et V1, timing, LIOBOX_BACKUP_PREFLIGHT | A/B : contrat actuel, limites et observations matérielles distinctes, conservés. |
| audits/AUDIT_ABLETON_2026-09-13.md | B : analyse unique d'un crash, non remplacée par une certification. |
| audits/CL_Cue_Editor_fiabilisation_2026-10-04.md | A/B : corrections, limites et procédure opérateur ; remplace l'audit initial. |
| docs/FULL_PRE_LIGHT_QUALIFICATION_2026-10-14.md | B : provenance du socle et anomalie de déconnexion, avec lien vers cet état courant. |
| docs/ui/* | B/D : proposition et notes de mise en œuvre encore utiles, conservées. |
| packaging/SHOW_AUDIO_VALIDATION.md | A/B : prérequis FFmpeg/Swift et limites de validation, conservés. |
| build_notes/SOURCES.txt, patch song-file-path-readonly.patch | B/A : provenance et extension AbletonOSC documentée, conservés. |
| Snapshots et captures listés ci-dessous | C : résultats synthétiques conservés, dumps et rendus sans usage actif retirés. |
| .venv, vendor/ffmpeg, .showcue_https | A : environnement et ressources locales utiles/privées, conservés. |
| .codex/environments/environment.toml | A/D : configuration projet sans chemin machine ni script de setup, conservée. |
| Sauvegardes .before-* distinctes et bundles locaux restants | D : utilité de secours ou travail distinct non exclue, conservés. |

## Vérification des références et documentation

Les chemins et noms des candidats ont été recherchés dans le code, les tests,
les scripts, le packaging et la documentation. Aucun fichier actif n'est retiré.
Les références documentaires restantes vers les captures/dumps supprimés sont
remplacées par une indication de leur disponibilité dans l'historique Git.
Les résultats de terrain MIDI et les mesures Builder restent dans leurs synthèses.

Les quatre anciennes notes Arrangement sont réunies dans docs/ARRANGEMENT.md,
avec la distinction beats/secondes et un lien vers les fonctions et tests actuels.
Les guides de l'ancien pack Ableton Web Remote renvoyaient à Installer_Mac.command,
à une application absente et à l'ancien crossfader MIDI. README/M4L ne présentent
plus l'AutoScene Live 10 supprimé antérieurement comme un device distribué.
Guides/EXPORT_KIT_TRANSPORT.txt décrit maintenant la reconstruction réelle du kit,
au lieu de prétendre que le script ne fait que copier une ancienne archive.

## Fichiers suivis supprimés — 32

- `docs/validated-local-midi-2026-09-30/backups.txt`
- `docs/validated-local-midi-2026-09-30/bonjour-only.patch`
- `docs/validated-local-midi-2026-09-30/captured-at.txt`
- `docs/validated-local-midi-2026-09-30/coremidi-inventory.json`
- `docs/validated-local-midi-2026-09-30/git-diff-before.patch`
- `docs/validated-local-midi-2026-09-30/git-head.txt`
- `docs/validated-local-midi-2026-09-30/git-status-before.txt`
- `docs/validated-local-midi-2026-09-30/installed-apps.json`
- `docs/validated-local-midi-2026-09-30/launchagent.txt`
- `docs/validated-local-midi-2026-09-30/midi-config-readonly.txt`
- `docs/validated-local-midi-2026-09-30/naming-references.txt`
- `docs/validated-local-midi-2026-09-30/processes-before.txt`
- `docs/validated-local-midi-2026-09-30/source-hashes-before.json`
- `docs/validated-local-midi-2026-09-30/status-before.json`
- `docs/validated-local-midi-2026-09-30/tests.txt`
- `docs/builder-ui/after-1280.png`
- `docs/builder-ui/after-1512.png`
- `docs/builder-ui/batch-1512.png`
- `docs/builder-ui/before-1512.png`
- `docs/builder-ui/metrics.json`
- `docs/builder-ui/remote-1512.png`
- `docs/builder-ui/sessions.png`
- `docs/screenshots/2026-09-18-cl-suite-working-state.png`
- `docs/REPO_CLEANUP_2026-10-07.md`
- `audits/CL_Cue_Editor_sessions_2026-10-04.md`
- `README_LISEZ_MOI.txt`
- `README_M4L_AB_FIXED.txt`
- `Guides/INSTALLATION_RAPIDE.txt`
- `README_ARRANGEMENT.txt`
- `README_ARRANGEMENT_CONDUITE.txt`
- `README_ARRANGEMENT_LOCATORS.txt`
- `README_ARRANGEMENT_SCENESTYLE.txt`

Les dumps MIDI sont des captures du Mac de septembre, pas des réglages de
production actifs. L'audit initial Cue Editor est remplacé par sa fiabilisation.
Le rapport de nettoyage du 7 octobre est remplacé par la qualification du socle
et ce rapport. Aucun RELEASE_*.md n'est présent dans cette base FULL : ceux du
lot Light n'ont pas été importés ni modifiés.

## Artefacts locaux non suivis supprimés

Les sorties PyInstaller de build/ ont été inspectées : TOC, PYZ, PKG, bytecode,
caches et exécutables de qualification reproductibles. Pas de source originale
nécessaire au fonctionnement. Les caches pytest/Python sont régénérables.
Les archives FULL du 25 et 27 septembre ont des sources et recettes plus
récentes conservées dans le socle ; aucun script/procédure courant n'en dépend.
Leurs checksums et BUILD_INFO spécifiques sont retirés avec la release 2.2.1.
Les PID ne correspondent à aucun processus vivant ; les trois dashboards
n'étaient ouverts par aucun processus et sont reconstruits depuis leurs sources.

- `build`
- `.pytest_cache`
- `__pycache__`
- `tests/__pycache__`
- `Releases/CL_Show_Control_2026-09-27_17-09.zip`
- `Releases/CL_Audio_Controller_2.2.1_2026-09-25_16-39-13`
- `osc_transport.py.backup-osc-meter-20260913-024040`
- `templates/index.html.backup-osc-meter-20260913-024059`
- `tools/cl_midi_network/CLMIDINetworkDashboard`
- `tools/cl_midi_network/CLMIDINetworkDashboard.arm64`
- `tools/cl_midi_network/CLMIDINetworkDashboard.x86_64`
- `.run/app.py.pid`
- `.run/showcue_builder_desktop.py.pid`
- `.run/showcue_desktop.py.pid`
- `.run/launcher_control.py.pid`
- `.run/show_audio_builder_desktop.py.pid`

Total des artefacts locaux retirés : 611,550,958 octets (environ 612 Mo).

Ces suppressions locales de fichiers déjà ignorés ne figurent pas dans les
commits de nettoyage. Les anciens fichiers suivis restent dans l'historique Git.

## Releases locales restantes — D, conservées

Les kits Light restent hors périmètre. Les candidats 2.3.0 viennent d'un autre
état de sources et ne constituent pas la version de cette base FULL. Les autres
bundles/essais non suivis peuvent constituer des secours ou validations distinctes :
leur abandon n'est pas suffisamment établi. Ne pas les supprimer par leur seul âge.

- `Releases/.DS_Store`
- `Releases/CL_Arrangement_Builder_Fix_2026-10-07`
- `Releases/CL_Audio_Controller_--help_2026-10-02_12-47-22`
- `Releases/CL_Autonome_2026-10-06`
- `Releases/CL_Installer_Corrige_2026-10-05`
- `Releases/CL_Kit_2.3.0`
- `Releases/CL_Kit_2.3.0_Final_Reconnect`
- `Releases/CL_Kit_2.3.0_Reconnect_Fix`
- `Releases/CL_Kit_Light_2.3.0`
- `Releases/CL_Kit_Light_2.3.0_Final_Reconnect`
- `Releases/CL_Kit_Light_2.3.0_Reconnect_Fix`
- `Releases/CL_Local_Applications_2026-10-07`
- `Releases/CL_MIDI_Interface_2026-10-06`
- `Releases/CL_MIDI_Interface_Final_2026-10-06`
- `Releases/CL_MIDI_Local_Simulator_2026-10-06`
- `Releases/CL_MIDI_Return_Fix_2026-10-06`
- `Releases/CL_Performance_Report_2026-10-06`
- `Releases/CL_Show_Control_2026-10-04`
- `Releases/CL_Show_Control_2026-10-04_connections`
- `Releases/CL_Show_Control_Backup_Buttons_2026-10-06`
- `Releases/CL_Show_Control_Backup_Memory_2026-10-06`
- `Releases/CL_Show_Control_Backup_UI_2026-10-06`
- `Releases/CL_Show_Control_Backup_UI_Final_2026-10-06`
- `Releases/CL_Show_Control_Bonjour_2026-10-06`
- `Releases/CL_Show_Control_Bonjour_Display_2026-10-06`
- `Releases/CL_Show_Control_Bonjour_Display_Final_2026-10-06`
- `Releases/CL_Show_Control_Builder_Preview_Fix_2026-10-07`
- `Releases/CL_Show_Control_Builder_Remote_And_Preview_Fix_2026-10-07`
- `Releases/CL_Show_Control_Builder_Remote_ReadOnly_2026-10-07`
- `Releases/CL_Show_Control_Builder_UI_Redesign_2026-10-07`
- `Releases/CL_Show_Control_Compact_2026-10-06`
- `Releases/CL_Show_Control_Compact_Final_2026-10-06`
- `Releases/CL_Show_Control_Direct_Scene_Backup_2026-10-06`
- `Releases/CL_Show_Control_Direct_Scene_Fix_2026-10-06`
- `Releases/CL_Show_Control_Direct_Scene_Immediate_2026-10-06`
- `Releases/CL_Show_Control_GO_Confirmation_2026-10-06`
- `Releases/CL_Show_Control_GO_Priority_2026-10-06`
- `Releases/CL_Show_Control_Import_And_Phase_Order_2026-10-07`
- `Releases/CL_Show_Control_Import_Compatibility_2026-10-07`
- `Releases/CL_Show_Control_Import_Feedback_2026-10-07`
- `Releases/CL_Show_Control_Import_Menu_2026-10-06`
- `Releases/CL_Show_Control_LTC_2026-10-06`
- `Releases/CL_Show_Control_LTC_Copy_Final_2026-10-06`
- `Releases/CL_Show_Control_LTC_Copy_Fix_2026-10-06`
- `Releases/CL_Show_Control_LTC_Smoothing_2026-10-06`
- `Releases/CL_Show_Control_Layout_2026-10-06`
- `Releases/CL_Show_Control_Layout_Final_2026-10-06`
- `Releases/CL_Show_Control_Light_2026-10-07`
- `Releases/CL_Show_Control_Mobile_Editor_2026-10-06`
- `Releases/CL_Show_Control_Mobile_Editor_2026-10-06_22-47-39`
- `Releases/CL_Show_Control_OSC_Diagnostic_2026-10-06`
- `Releases/CL_Show_Control_OSC_Harmonized_2026-10-06`
- `Releases/CL_Show_Control_OSC_Timeout_2026-10-06`
- `Releases/CL_Show_Control_Phases_Messages_2026-10-06`
- `Releases/CL_Show_Control_Remote_Buttons_2026-10-06`
- `Releases/CL_Show_Control_ShowCue_Permissions_2026-10-06`
- `Releases/CL_Show_Control_ShowQ_Calls_2026-10-06`
- `Releases/CL_Show_Control_ShowQ_Layout_2026-10-06`
- `Releases/CL_Show_Control_ShowQ_Sidebar_2026-10-06`
- `Releases/CL_Show_Control_Startup_2026-10-06`
- `Releases/CL_Show_Control_Tools_Fix_2026-10-06`
- `Releases/bonjour-test`
- `Releases/showcue-phase-test`
- `Releases/showcue-ui-final`
- `Releases/showcue-ui-test`

## Versionnement constaté, sans changement de numéro

| Source | Valeur et rôle |
| --- | --- |
| CL Audio Controller.spec | 2.2.0 / build 6 ; autorité effective pour le bundle Show Control construit depuis ces sources. |
| README et CHANGELOG | 2.2.0 ; évolutions postérieures non publiées. |
| scripts/build_release.sh | VERSION par défaut 2.2.0 ; nom du kit paramétrable. |
| scripts/export_transport_kit.command | CL_AUDIO_VERSION par défaut 2.2.1 ; nom de kit différent du .spec, sans source centrale assurant leur concordance. |
| BUILD_ENVIRONMENT.md | Relevés historiques 2.1.0 / build 5, maintenant distingués du .spec actuel. |
| CL ShowCue.spec, CL ShowCue Builder.spec, CL Show Audio Builder.spec | 1.0.0 / build 1 pour les composants, indépendants du kit. |
| scripts/build_midi_console_package.sh | 1.0.0 par défaut, kit MIDI distinct. |
| scripts/build_configuration_checker_app.sh | 0.1.0 / build 1 pour le vérificateur. |
| scripts/install_desktop_kit_builder.sh | 1.0.0 pour l'outil de création de kit. |
| resources/app_identity.json | Noms/icônes/alias, aucune version de release. |
| build_identity.py | BUILD_ID CL_Audio_Controller-2.0.1-identity-v1 : identité du protocole launcher/serveur ; ne pas l'assimiler à une version de distribution ni la changer pendant ce nettoyage. |

Il n'existe pas de source unique fiable pour toutes les versions et builds.
Proposition future : choisir explicitement la politique kit/composants et
centraliser uniquement les métadonnées de distribution, puis faire vérifier
la concordance des Info.plist et du nom de kit. Cette normalisation n'est pas
réalisée ici ; aucune version 2.3.0 n'est récupérée depuis Light.
Les versions des dépendances et formats de données ne sont pas des releases CL.

## .gitignore et checksum actif

Ajouts : /releases/ (variante minuscule), *.pid, *.bak_release_version,
*.backup-[0-9]*. Les exclusions build/dist/Releases/logs/caches/.run/bundles et
sauvegardes de stamping restent précises ; aucune ressource suivie n'est ignorée
nouvellement. Les captures historiques ne sont pas globalement ignorées, pour
permettre de futures références visuelles volontaires.

M4L/Install/SHA256SUMS.txt reste actif. Une empreinte était périmée :
ParadisLatin_AutoScene.js a évolué dans l'historique alors que le hash n'avait
pas suivi. Le script est identique à la copie de Devices et n'est pas modifié.
Seul son hash est actualisé. Les six entrées du manifeste passent ensuite.

## Validation finale

- Python FULL complet : **1229 réussis, 0 échec, 1 ignoré, 122 sous-tests réussis**
  (76,40 s), sécurité et sorties temporaires isolées.
- JavaScript : **29 fichiers/suites réussis**, 0 échec, incluant Chrome headless
  avec routes interceptées et données fictives.
- Syntaxe : 175 fichiers Python/spec, 22 scripts shell et 47 fichiers JS/CJS,
  aucune erreur. Pas d'exécution de PyInstaller ou d'installateur.
- Les specs sont aussi exercées par les tests de packaging avec factories simulées.
- Checksum M4L : six fichiers conformes après actualisation.
- Contrôles git diff --check réussis, vérification des références retirées.
- Logs détaillés de cette passe : /private/tmp/cl-current-full-*.log/json.

Les tests Python sont lancés avec PYTHONDONTWRITEBYTECODE=1, cacheprovider
 désactivé et CL_SECURITY_DIRECTORY dans /private/tmp. Ports locaux et tests
natifs isolés nécessitent des permissions hors sandbox ; aucun matériel de
spectacle ni réglage de production n'est utilisé comme destination d'écriture.

Limites conservées : anomalie de seconde confirmation d'identité Ableton laissant
connected=true documentée dans la qualification pré-Light ; dépendance LTC
framerate.js manquante déjà signalée ; aucune qualification matérielle, Mac vierge,
notarisation ou reconstruction de release. La propreté du dépôt ne vaut pas
certification de production. Tous les installateurs actuellement référencés,
les formats de production et leurs tests restent en place.
