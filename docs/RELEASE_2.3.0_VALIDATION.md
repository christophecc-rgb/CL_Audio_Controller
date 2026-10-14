# Validation de release CL Kit 2.3.0 — 9 octobre 2026

## Décision proposée

Deux archives candidates construites et signées ad hoc. Aucun commit, merge, tag, push, publication ni installation. Les applications FULL installées n'ont pas été remplacées. Branche feature/local-light. La validation n'est pas entièrement verte : un échec de mock natif préexistant subsiste et certains essais de distribution restent à faire.

## Changements de cette passe

Source centrale release_version.py : version 2.3.0, build 23001. Specs et scripts utilisent ces valeurs ; les copies distribuées des applications partenaires sont harmonisées sans modifier leurs dépôts. Le stamp conserve chaque bundle identifier et refuse un recul de build numérique. Les signatures sont refaites après le stamp.

La build Light force le moteur commun même si CL_LIGHT_ENGINE=legacy est injecté. Le runtime historique reste dans le dépôt pour le développement, mais light_runtime et light_timing sont exclus du PYZ final. Le rendu Light validé est conservé. Aucun changement de logique MIDI/Program Change dans cette passe.

Fichiers créés/modifiés pour la release :

- release_version.py
- scripts/stamp_release_bundles.py
- CL Audio Controller.spec
- CL ShowCue.spec
- CL ShowCue Builder.spec
- CL Show Audio Builder.spec
- CL Show Control Light.spec
- launcher_light.py
- runtime_startup.py
- scripts/build_release.sh
- scripts/export_transport_kit.command
- scripts/build_light_kit.sh
- packaging/Installer_CL_Light.command
- README.md
- CHANGELOG.md
- docs/RELEASE_2.3.0.md
- tests/test_packaging.py
- tests/test_light_packaging.py
- tests/test_release_version.py

Les modifications antérieures du moteur commun, du panneau sécurité et de leurs tests sont conservées. Elles figurent dans l'état Git ci-dessous ; les gros diffs ne sont pas tous apparus pendant la construction de cette release.

Sauvegardes : /private/tmp/CL_RELEASE_230_20261009/. Les copies distribuées d'AbletonOSC avant retrait des tests, scripts de développement, .github et sauvegardes de patch sont dans plugin_distribution_backups/. Aucun fichier source du plugin n'a été supprimé.

## Architecture Light

launcher_light → app.py / moteur commun → ableton_runtime, go_core, scene_timing, common_light_runtime → interface Light et sécurité remote existante. Pas de moteur parallèle en distribution. Services consoles, RTP, backup, LTC/MTC et Arrangement désactivés par le profil. Les imports transitifs de l'hôte commun incluent encore des définitions FULL (dont hot_backup_sync, ltc_receiver, showcue_builder et pypdf), sans démarrer ces services. Ce couplage d'import est conservé plutôt qu'exclure aveuglément des dépendances.

## Versionnement

Version distribuée de toutes les applications : 2.3.0 ; CFBundleVersion : 23001. Identifiants FULL conservés ; Light : com.claudio.showcontrollight. BUILD_ID de protocole/identité conserve 2.0.1-identity-v1. Les versions des dépendances et protocoles ne changent pas.

Occurrences 2.2.0/2.2.1 résiduelles relevées dans /private/tmp/cl230-residual-versions.txt : changelog et documentation historiques, anciennes releases, noms de fixtures historiques, itsdangerous 2.2.0 et sa licence. Elles ne représentent pas la release courante. 2.2.1 provenait du commit ba9db5c (26 septembre) ; une archive avait déjà été construite le 25 septembre depuis df556ec. Aucun nouveau tag créé.

## Contenu FULL

Applications et enveloppes exactes :

- Désinstaller la Suite CL
- CL Cue Editor
- CL Ableton Remote
- CL Audio Export
- CL MIDI Network Manager
- CL Arrangement Builder
- CL MIDI Performance Monitor
- CL MIDI & RTP Diagnostic
- CL Show Control
- CL MTC Bridge
- CL MIDI Analyzer
- CL Sync Meter
- CL MIDI RTP Agent
- CL ShowCue
- Installer la Suite CL

Soit 13 applications d'exploitation et 2 enveloppes installation/désinstallation. Show Backup n'est pas inclus : le récepteur conforme au marqueur HMAC du catalogue n'est pas construit. Ressources : CL_Transport, bibliothèques console, outils réseau, Max for Live, AbletonOSC CL, Remote Script Arrangement et documentation. Les fichiers de production n'ont pas été édités. Les tests/outils de développement et sauvegardes de patch du plugin sont retirés des copies du kit, pas des sources.

## Contenu Light

Une seule application : CL Show Control Light.app ; AbletonOSC avec patches CL ; installateur Installer CL Light.command ; documentation, manifeste, architectures et sommes SHA256. Pas de ShowCue/Builder/Arrangement autonome, outils console, Performance Monitor, binaires MTC, ressources console ni runtime Light legacy. Flask, python-osc, pywebview Cocoa et sécurité remote sont embarqués. Aucun mot de passe/appareil autorisé/certificat privé n'est fourni pour configurer un autre Mac.

## Résultats des tests

- Python complet : 1353 réussis, 1 ignoré, 122 sous-tests, 1 échec.
- Échec inchangé : tests/test_simulator_dashboard_state.py::test_dashboard_simulator_ownership[test_simulator_dashboard_control.m]. Le mock CLMemoryDefaults n'implémente pas stringForKey. Déjà présent lors de l'audit avant cette passe, indépendant du packaging ; non corrigé dans cette mission.
- Sécurité ciblée : 44 réussis.
- JavaScript : 27/27 suites réussies.
- Packaging/version Light ciblé : 21 réussis, 3 sous-tests.
- Syntaxe Python/shell vérifiée ; syntaxe JS vérifiée dans la passe sécurité ; git diff --check OK.
- Architectures : FULL 379 Mach-O et Light 67 Mach-O universal2.
- Codesign : vérification deep/strict ; installateur FULL vérifié après extraction de l'archive finale.

## Runtime sur cette machine

FULL construit : démarrage, Set/scènes, GO, Pause→GO, STOP et ShowCue validés. Panneau sécurité testé avec répertoire isolé : configuration/admin séparés, armement/désarmement, mode spectacle et refus 403 de sortie sans admin. Live rouvert avec SHOW CASSIS ; génération passée à 3 et état arrêté récupéré. Le statut de déconnexion FULL a été relevé trop tôt et affichait encore connected=true ; ne constitue pas une mesure validée de son délai de détection.

LIGHT construit : hostile CL_LIGHT_ENGINE=legacy ignoré, common confirmé ; prev/next changent la préparation sans lancement ; GO lance l'index préparé et prépare le suivant ; STOP et raccourcis Entrée/Échap validés ; durée courante et préparée disponibles ; progression réelle observée. Après fermeture de Live, ableton_available=false, set_available=false, state=unavailable. Après réouverture du Set, génération 3, GO/STOP à nouveau fonctionnels. Exemple : PROUD MARY durée 94 s, progression 0.256→2.262 s en environ 2 s, suivante CANT STOP1 durée 160 s.

Live a été sauvegardé avant fermeture conformément à l'autorisation, avec copie préalable du .als dans la sauvegarde. Les configurations de sécurité des essais sont isolées sous /private/tmp. Aucun service console/backup Light observé ; les contrôles de profil sont aussi couverts par les tests.

Les ouvertures Arrangement Builder, Cue Editor et Audio Export n'ont pas toutes une confirmation visuelle exploitable ; ne pas les considérer validées par une simple tentative de lancement. Le remote iPhone de cette build finale et le parcours d'installation sur Mac vierge restent à confirmer. Les validations antérieures du remote commun et les tests sécurité ne remplacent pas cet essai final.

## Artefacts

- `/Users/mbprochris/Documents/GitHub/CL_Audio_Controller/Releases/CL_Kit_2.3.0/CL_Kit_2.3.0_2026-10-09_011003_universal2.zip` — 255,655,810 octets (255.66 Mo).
- `/Users/mbprochris/Documents/GitHub/CL_Audio_Controller/Releases/CL_Kit_Light_2.3.0/CL_Kit_Light_2.3.0_universal2.zip` — 23,496,097 octets (23.50 Mo).

Les sommes SHA256 sont à côté des archives. ZIP uniquement, aucun DMG supplémentaire. Light est environ 10.9 fois plus petit que le kit FULL ; cela compare les kits et non les seules applications.

## Risques et limites

Signature ad hoc, absence de notarisation Apple. Installation côte à côte possible grâce aux identités distinctes ; exécution simultanée NON prise en charge (ports HTTP/HTTPS/OSC communs). Fermer FULL avant Light. Ressources média et Live non inclus. Le test sur Mac vierge reste nécessaire pour confirmer la portabilité ; les lancements de la build depuis /private/tmp et la présence des modules embarqués prouvent l'absence de dépendance runtime normale au dépôt, sans constituer un test sur une autre machine. Les chemins de compilation peuvent subsister dans les métadonnées de bytecode et les données de show doivent être vérifiées avec les médias de la machine cible.

Les builds parallèles ont rencontré une collision de cache PyInstaller ; constructions finales réalisées avec caches FULL et Light distincts. Pour reproduire les builds simultanés, définir PYINSTALLER_CONFIG_DIR distinct pour chaque build.

## Exclusions conservées, non suivies

- docs/SHOWCUE_MOBILE_EDITOR.md
- packaging/Installer_CL_Autonome.command
- scripts/package_autonomous.py
- static/marquee/marquee_off.png
- static/marquee/marquee_on.png
- static/marquee/showcue-marquee.css

## État Git final

```text
 M CHANGELOG.md
 M "CL Audio Controller.spec"
 M "CL Show Audio Builder.spec"
 M "CL ShowCue Builder.spec"
 M "CL ShowCue.spec"
 M README.md
 M app.py
 M launcher_control.py
 M osc_transport.py
 M remote_security.py
 M scripts/build_release.sh
 M scripts/export_transport_kit.command
 M static/security-panel.html
 M static/security-panel.js
 M tests/js/render_remote_fixture.py
 M tests/test_development_access.py
 M tests/test_hot_backup_sync.py
 M tests/test_network_target_independence.py
 M tests/test_osc_transport.py
 M tests/test_packaging.py
 M tests/test_phase2_security.py
 M tests/test_remote_passive_feedback.py
 M tests/test_remote_tls_setup.py
 M tests/test_scene_backup_udp.py
 M tests/test_security_panel_network.py
?? "CL Show Control Light.spec"
?? ableton_runtime.py
?? app_mode.py
?? common_light_runtime.py
?? docs/LOCAL_LIGHT_PHASE3.md
?? docs/LOCAL_LIGHT_PHASE4.md
?? docs/LOCAL_LIGHT_TIMING.md
?? docs/RELEASE_2.3.0.md
?? docs/RELEASE_2.3.0_VALIDATION.md
?? docs/SECURITY_LIGHT_KIT_AUDIT_2026-10-09.md
?? docs/SHOWCUE_MOBILE_EDITOR.md
?? go_core.py
?? launcher_light.py
?? light_runtime.py
?? light_timing.py
?? packaging/Installer_CL_Autonome.command
?? packaging/Installer_CL_Light.command
?? release_version.py
?? runtime_startup.py
?? scene_timing.py
?? scripts/build_light_kit.sh
?? scripts/package_autonomous.py
?? scripts/stamp_release_bundles.py
?? static/light.css
?? static/light.js
?? static/marquee/
?? templates/light.html
?? tests/js/test_light_ui.cjs
?? tests/test_common_ableton_runtime.py
?? tests/test_common_light_runtime.py
?? tests/test_light_packaging.py
?? tests/test_light_timing_selection.py
?? tests/test_local_light_go.py
?? tests/test_local_light_runtime.py
?? tests/test_release_version.py
```

## Diff des fichiers suivis

Les fichiers non suivis ne sont pas comptés par git diff --stat.

```text
 CHANGELOG.md                              |   7 +
 CL Audio Controller.spec                  |   5 +-
 CL Show Audio Builder.spec                |   5 +-
 CL ShowCue Builder.spec                   |   5 +-
 CL ShowCue.spec                           |   5 +-
 README.md                                 |   6 +-
 app.py                                    | 878 ++++++------------------------
 launcher_control.py                       |   7 +
 osc_transport.py                          |  34 +-
 remote_security.py                        |   7 -
 scripts/build_release.sh                  |  15 +-
 scripts/export_transport_kit.command      |  10 +-
 static/security-panel.html                | 774 ++++++++++++++++++++++++--
 static/security-panel.js                  | 122 ++++-
 tests/js/render_remote_fixture.py         |   4 +-
 tests/test_development_access.py          |   5 +-
 tests/test_hot_backup_sync.py             |   3 +-
 tests/test_network_target_independence.py |   4 +-
 tests/test_osc_transport.py               |   2 +-
 tests/test_packaging.py                   |   6 +-
 tests/test_phase2_security.py             |  50 ++
 tests/test_remote_passive_feedback.py     |  14 +-
 tests/test_remote_tls_setup.py            |   2 +-
 tests/test_scene_backup_udp.py            |  17 +-
 tests/test_security_panel_network.py      |  12 +-
 25 files changed, 1197 insertions(+), 802 deletions(-)
```

## Proposition après validation utilisateur

Message : « Préparer les kits CL 2.3.0 et le moteur commun Light ».
Tag proposé : v2.3.0, seulement après validation des artefacts et résolution/acceptation explicite des limites restantes. Aucun de ces actes n'a été exécuté.

## Qualification finale des ZIP existants

Le rapport complémentaire faisant autorité pour la dernière passe est `RELEASE_2.3.0_FINAL_QUALIFICATION.md`. Nouvelle extraction, signatures et architectures vérifiées. Une anomalie runtime FULL est désormais reproduite : `connected=true` subsiste pendant 22 secondes après fermeture réelle de Live. La qualification finale reste suspendue ; aucun candidat ZIP reconstruit.
