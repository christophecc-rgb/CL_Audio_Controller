# Qualification finale des candidats CL Kit 2.3.0

## Actualisation — reconstruction avec correction transport, 9 octobre 2026

Cette section est la qualification actuelle ; les sections suivantes conservent les résultats de la passe précédente comme historique. Aucun commit, tag, push, publication, installation ni staging.

### Candidats reconstruits

- FULL : `Releases/CL_Kit_2.3.0_Reconnect_Fix/CL_Kit_2.3.0_2026-10-09_022425_universal2.zip` — 255 654 555 octets.
- Light : `Releases/CL_Kit_Light_2.3.0_Reconnect_Fix/CL_Kit_Light_2.3.0_universal2.zip` — 23 499 281 octets.
- 16 bundles vérifiés (15 FULL, 1 Light) : version 2.3.0, build 23001, exécutables présents, codesign --verify --deep --strict OK. Signatures ad hoc.
- Correction transport vérifiée dans le code embarqué du PYZ FULL : branche None et message AbletonOSC indisponible présents.
- Extraction macOS avec ditto pour préserver les liens symboliques des bundles.

### Régression et validations

Trois tests ajoutés dans tests/test_common_ableton_runtime.py : réponse valide même arrêté, timeout transport sans faux succès, reconnexion sur le même runtime. Passe ciblée : 156 réussis, 1 ignoré, 18 sous-tests. Suite complète avec accès aux ports locaux et journal de sécurité isolé : 1356 réussis, 1 ignoré, 122 sous-tests, 1 échec déjà identifié dans le mock natif test_simulator_dashboard_control.m (CLMemoryDefaults incomplet). Aucun code applicatif modifié durant cette passe.

JavaScript : 23/27 suites réussies ; quatre suites navigateur non exécutables dans l’environnement courant, car le Chromium headless attendu par Playwright est absent (test_console_health_ui, test_paradis_network, test_remote_design_system, test_session_skins). Ce résultat n’est pas présenté comme une régression applicative. Test JS Light et syntaxe Light OK. Syntaxe Python et git diff --check OK.

### Runtime FULL — NON QUALIFIÉ

Connexion initiale réelle : connected=true, Connecté à AbletonOSC. Après fermeture réelle de Live (aucun processus Live, aucun port UDP 11000), connected reste true pendant les 40 relevés supplémentaires à 500 ms. Réouverture et chargement de SHOW CASSIS : connected=true.

La correction transport est bien embarquée, mais ne couvre pas une autre sortie anticipée : ableton_runtime.py:133-134 retourne None si la confirmation /live/song/get/file_path est absente ; refresh_names_and_transport():294-296 retourne alors False avant la requête transport sans actualiser connected. Ce chemin est une explication de code précise à couvrir par une régression et une correction supplémentaire ; le chemin exact du thread n’a pas été instrumenté, donc la causalité runtime reste à confirmer. Le candidat FULL ne doit pas être publié comme validé.

### Runtime Light

Scènes récupérées depuis SHOW CASSIS. PREV/NEXT préparent sans lancer. GO lance la scène préparée ; STOP confirmé. Durée courante 709 s, progression environ 0,26→2,26 s en 2 s, restant cohérent. Fermeture Live : ableton_available=false, state=unavailable, erreur Ableton indisponible. Réouverture et recharge du Set effectuées ; PREV/NEXT, GO, timing et STOP après reconnexion tous réussis (light-reconnected-actions.log). Aucun fichier de fonctionnement Light modifié dans cette passe.

### Git et preuves

Branche feature/local-light ; index vide. ableton_runtime.py reste non suivi et DOIT entrer dans le commit final avec les autres modules du moteur commun. La liste des 57 fichiers proposée dans la section historique reste la liste de consolidation ; les six exclusions historiques restent présentes et non suivies. ZIPs, bundles, journaux et sauvegardes hors commit.

Sauvegardes ciblées avant changement : /private/tmp/CL230_RECONNECT_FIX_20261009/backups/. Résultats et états runtime : /private/tmp/CL230_RECONNECT_FIX_20261009/.

---

## Historique de la qualification précédente

## 1. FULL ZIP validé : NON pour qualification complète

Audit du package : OK. GO, Pause→GO, STOP, interface principale et sécurité locale : OK. Réserve bloquante : après fermeture réelle de Live, aucun processus Live ne subsiste mais /status retourne connected=true sur les 12 relevés espacés de 2 s (0 à 22 s). L’interface pouvait encore afficher SYSTÈME PRÊT. Aucun diagnostic de cause complète ni correction effectué dans cette qualification. La reconnexion FULL avait récupéré les scènes dans la passe précédente, mais la détection de déconnexion n’est pas qualifiée.

## 2. Light ZIP validé : OUI pour les contrôles locaux effectués

Pas de validation physique globale implicite. Moteur commun embarqué ; light_runtime/light_timing absents du PYZ. Injection CL_LIGHT_ENGINE=legacy ignorée par la build. Démarrage sans Live : Ableton indisponible, aucune action autorisée. Réouverture du Set : génération 2, scènes récupérées. PREV/NEXT préparent sans lecture ; GO lance exactement l’index préparé et prépare le suivant ; STOP confirmé. Progression 0,257→2,262 s en environ 2 s ; durée courante 709 s et préparée 244 s. Entrée lance, Échap arrête, interface ARRÊTÉ confirmée. Un premier essai pendant le chargement du Set a été refusé 409 ; relancé une fois le Set disponible, il passe. Arrêt par SIGTERM : port 5050 libéré. Fermeture native de toutes les fenêtres complémentaires non qualifiée par les seuls SIGTERM.

## 3. Applications complémentaires

Toutes sont version 2.3.0/build 23001, exécutables présents, signatures valides. TEST PARTIEL distingue un smoke test processus d’une validation fonctionnelle complète. Aucune application n’a été réparée pour compenser une absence de matériel.

| Application | Résultat | Portée |
|---|---|---|
| CL Show Control.app | TEST PARTIEL | Parcours FULL OK, anomalie connected après fermeture Live. |
| CL Ableton Remote.app | TEST PARTIEL | Processus vivant après 4 s, aucun message d’erreur immédiat ; terminaison de test vérifiée, fonctions métier non exercées. |
| CL Arrangement Builder.app | TEST PARTIEL | Processus stable au lancement ; génération Arrangement non effectuée. |
| CL Audio Export.app | TEST PARTIEL | Ouverture 12 s sans erreur avec FULL actif ; sans serveur, erreur HTTP attendue. Export de médias non effectué. |
| CL Cue Editor.app | TEST PARTIEL | Processus stable ; édition/import destructif non effectué. |
| CL MIDI & RTP Diagnostic.app | TEST PARTIEL | Processus vivant après 4 s, aucun message d’erreur immédiat ; terminaison de test vérifiée, fonctions métier non exercées. |
| CL MIDI Analyzer.app | TEST PARTIEL | Processus vivant après 4 s, aucun message d’erreur immédiat ; terminaison de test vérifiée, fonctions métier non exercées. |
| CL MIDI Network Manager.app | TEST PARTIEL | Ouverture/terminaison ; console physique non testée. |
| CL MIDI Performance Monitor.app | TEST PARTIEL | Processus vivant après 4 s, aucun message d’erreur immédiat ; terminaison de test vérifiée, fonctions métier non exercées. |
| CL MIDI RTP Agent.app | TEST PARTIEL | Correspondant CL Ableton Distant absent ; liaison RTP non testée. |
| CL MTC Bridge.app | TEST PARTIEL | Bridge prêt, ports IAC détectés ; émission vers appareil non testée. |
| CL ShowCue.app | TEST PARTIEL | Processus vivant après 4 s, aucun message d’erreur immédiat ; terminaison de test vérifiée, fonctions métier non exercées. |
| CL Sync Meter.app | TEST PARTIEL | Ouverture ; signal MTC externe non testé. |

Installateur et désinstallateur FULL : NON TESTABLE ICI pour l’installation effective (non exécutés), identité/signature/exécutable OK. Show Backup : absent du catalogue distribué, comme indiqué dans le rapport précédent ; ne pas présenter ce kit comme incluant Show Backup.

## 4. Isolation hors dépôt

Deux ZIP extraits à neuf sous /private/tmp/CL230_FINAL_QUALIFICATION_20261009/full et light ; exécutables lancés directement depuis ces extractions, répertoire courant temporaire. Sécurité de test isolée pour FULL/Light. Pas de déplacement ni suppression du dépôt. Le dépôt et les réglages existants du Mac restent présents : ce contrôle ne prouve pas une installation entièrement vierge. Les chemins de bibliothèques absolus inspectés par otool ne nécessitent aucun fichier hors bundle sauf bibliothèques système ; les pseudo-entrées otool correspondant au nom du binaire lui-même sont exclues de cette conclusion. Aucune référence textuelle /Users/mbprochris ou au dépôt trouvée dans les formats inspectés. Cinq fichiers FULL référencent /private/tmp pour logs/états/mktemp : usage runtime légitime, pas dépendance à un artefact de build. Les métadonnées de compilation des binaires/bytecodes ne constituent pas en elles-mêmes une dépendance runtime ; audit exhaustif de toutes les ressources externes de shows non effectué.

Inventaires exacts : full-inventory.txt et light-inventory.txt, audit plists/signatures : bundle-audit.json, dépendances : dependencies.json, modules Python : light-pyz-modules.txt, dans le dossier temporaire ci-dessus. Frameworks Python 3.14/PySide6-Qt pour les outils concernés, Python/pywebview Cocoa/Flask/python-osc pour Light. Aucun manque de bibliothèque constaté au lancement.

Light conserve des définitions FULL transitives (hot_backup_sync, ltc_receiver, showcue_builder, pypdf) à cause du module app commun ; services désactivés, pas de binaires outils MTC/console/Performance Monitor ni runtime Light historique. Pas de suppression aveugle supplémentaire. Le kit Light ne fournit pas d’application Builder/ShowCue autonome.

## 5. Validation iPhone physique en attente utilisateur

Effectuer séparément FULL puis Light, jamais simultanément :

1. Lancer la copie packagée, préparer HTTPS depuis sa maintenance ; ouvrir l’URL proposée, normalement https://MacChris.local:8443/ (FULL ShowCue : /show-info).
2. Depuis Safari iPhone, demander l’appairage par le QR/URL du panneau.
3. Approuver l’appareil sur le Mac ; contrôler ses permissions.
4. Armer explicitement les télécommandes.
5. Vérifier affichage/retour d’état puis GO/STOP et PREV/NEXT ; édition ShowCue selon permissions en FULL.
6. Passer Configuration→Spectacle ; vérifier que la sortie requiert l’admin local.
7. Fermer/rouvrir Safari ou reconnecter le Wi-Fi ; vérifier appareil et commandes.
8. Révoquer l’appareil test ; vérifier refus, puis le réappairer si souhaité.

HTTPS était inactif dans la configuration de test vierge : ne pas supposer cette URL prête avant préparation. Aucun test physique simulé, aucune validation de certificat iPhone revendiquée.

## 6. Mac vierge physique non testé

Installation effective et fonctionnement avec un nouveau compte/Mac, médias et AbletonOSC à installer : en attente. Aucun remplacement d’application installée.

## 7–8. Versions, signatures, intégrité

16 bundles audités : 13 applications FULL, 2 enveloppes, 1 Light ; tous 2.3.0/23001, codesign deep/strict OK. FULL 379 Mach-O universal2 ; Light 67. Vérification universal2 statique, exécution native sur ce Mac seulement. Signatures ad hoc, pas de notarisation. Sommes internes : 1073 entrées FULL et 168 Light, zéro fichier absent ou somme différente.

- `/Users/mbprochris/Documents/GitHub/CL_Audio_Controller/Releases/CL_Kit_2.3.0/CL_Kit_2.3.0_2026-10-09_011003_universal2.zip` : 255655810 octets ; SHA256 `2321ce1b6e97dcf1305b51d68cef6aada7de46582987042e22109660f53fb405`.
- `/Users/mbprochris/Documents/GitHub/CL_Audio_Controller/Releases/CL_Kit_Light_2.3.0/CL_Kit_Light_2.3.0_universal2.zip` : 23496097 octets ; SHA256 `5cd7bfc001970f5f98f0526d8db22851be4a8fea73bfccb37bc876bb94770ddd`.

## 9. Tests automatisés

Baseline validée précédente conservée : JavaScript 27/27 ; Python 1353 réussis, 1 ignoré, 122 sous-tests et 1 échec préexistant. Cet échec est technique : test_simulator_dashboard_ownership[test_simulator_dashboard_control.m], mock CLMemoryDefaults sans stringForKey, non modifié ici. Cette qualification ne prétend donc pas que toute la suite Python est verte.

Nouvelle passe : tests/test_packaging.py, tests/test_light_packaging.py, tests/test_release_version.py, tests/test_phase2_security.py : 37 réussis, 3 sous-tests. Syntaxe Python des fichiers proposés OK ; git diff --check OK. Aucun JS applicatif modifié pendant cette passe. Logs runtime et résultats HTTP conservés dans le dossier temporaire. Test des demandes d’approbation couvert automatiquement ; parcours appareil physique en attente.

## 10. Fichiers proposés pour un futur commit

Proposition seulement, aucune mise à l’index. Sources communes/profil/GO/timing, UI Light et Security Panel, sécurité et transport, scripts/specs/version, tests et docs associés. Les fichiers historiques Light restent versionnables comme voie de développement, sans les embarquer dans le package.

- `CHANGELOG.md`
- `CL Audio Controller.spec`
- `CL Show Audio Builder.spec`
- `CL Show Control Light.spec`
- `CL ShowCue Builder.spec`
- `CL ShowCue.spec`
- `README.md`
- `ableton_runtime.py`
- `app.py`
- `app_mode.py`
- `common_light_runtime.py`
- `docs/LOCAL_LIGHT_PHASE3.md`
- `docs/LOCAL_LIGHT_PHASE4.md`
- `docs/LOCAL_LIGHT_TIMING.md`
- `docs/RELEASE_2.3.0.md`
- `docs/RELEASE_2.3.0_FINAL_QUALIFICATION.md`
- `docs/RELEASE_2.3.0_VALIDATION.md`
- `docs/SECURITY_LIGHT_KIT_AUDIT_2026-10-09.md`
- `go_core.py`
- `launcher_control.py`
- `launcher_light.py`
- `light_runtime.py`
- `light_timing.py`
- `osc_transport.py`
- `packaging/Installer_CL_Light.command`
- `release_version.py`
- `remote_security.py`
- `runtime_startup.py`
- `scene_timing.py`
- `scripts/build_light_kit.sh`
- `scripts/build_release.sh`
- `scripts/export_transport_kit.command`
- `scripts/stamp_release_bundles.py`
- `static/light.css`
- `static/light.js`
- `static/security-panel.html`
- `static/security-panel.js`
- `templates/light.html`
- `tests/js/render_remote_fixture.py`
- `tests/js/test_light_ui.cjs`
- `tests/test_common_ableton_runtime.py`
- `tests/test_common_light_runtime.py`
- `tests/test_development_access.py`
- `tests/test_hot_backup_sync.py`
- `tests/test_light_packaging.py`
- `tests/test_light_timing_selection.py`
- `tests/test_local_light_go.py`
- `tests/test_local_light_runtime.py`
- `tests/test_network_target_independence.py`
- `tests/test_osc_transport.py`
- `tests/test_packaging.py`
- `tests/test_phase2_security.py`
- `tests/test_release_version.py`
- `tests/test_remote_passive_feedback.py`
- `tests/test_remote_tls_setup.py`
- `tests/test_scene_backup_udp.py`
- `tests/test_security_panel_network.py`

## 11. Exclusions

Six exclusions existantes, présentes sur disque et non suivies :

- `docs/SHOWCUE_MOBILE_EDITOR.md`
- `packaging/Installer_CL_Autonome.command`
- `scripts/package_autonomous.py`
- `static/marquee/marquee_off.png`
- `static/marquee/marquee_on.png`
- `static/marquee/showcue-marquee.css`

ZIP/Releases non versionnés historiquement (git ls-files Releases vide) : ne pas inclure. Aucun cache, log, certificat/clé privée, backup local ou /private/tmp proposé. Vérification des marqueurs de clés privées dans les fichiers proposés : aucun trouvé ; elle ne constitue pas un audit de secrets universel.

## 12–13. Commit et tag proposés

`Release 2.3.0: shared Light engine and security updates`

Tag proposé `v2.3.0`, conforme aux tags existants v2.0.0/v2.1.0. Ne pas exécuter avant levée des réserves et validation humaine finale. Aucun tag créé.

## 14. Git final

Index vide ; branche feature/local-light. État détaillé ci-dessous (les six exclusions sont incluses dans le status car volontairement non suivies).

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
?? static/marquee/marquee_off.png
?? static/marquee/marquee_on.png
?? static/marquee/showcue-marquee.css
?? templates/light.html
?? tests/js/test_light_ui.cjs
?? tests/test_common_ableton_runtime.py
?? tests/test_common_light_runtime.py
?? tests/test_light_packaging.py
?? tests/test_light_timing_selection.py
?? tests/test_local_light_go.py
?? tests/test_local_light_runtime.py
?? tests/test_release_version.py
?? docs/RELEASE_2.3.0_FINAL_QUALIFICATION.md
```

## 15. Blocages et prochaine décision

Qualification globale NON : anomalie FULL connected après fermeture Live à diagnostiquer ; tests fonctionnels complémentaires limités au smoke test ; iPhone physique et Mac vierge en attente ; un test Python natif préexistant non vert. Aucun nouveau défaut de packaging démontré et aucune reconstruction. Ne pas publier les ZIP comme entièrement qualifiés tant que ces réserves ne sont pas arbitrées. Les preuves Light locales sont positives.
