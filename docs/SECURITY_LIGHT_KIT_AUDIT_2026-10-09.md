# Audit Security Panel, moteur commun Light et distribution CL — 9 octobre 2026

Audit sur `feature/local-light`. Aucun commit, indexation, merge, push, tag, changement de version, build final ou installation. Aucun fichier Light supprimé. Production CSV/CLF/RTP et logique MIDI/Program Change préservées.

## 1. Security Panel

Apparence validée conservée : CSS inchangé, administration rouge/verte, droits repliables, ajout iPhone fermé par défaut, bouton spectacle dynamique. Configuration et administration déverrouillée sont indépendantes. L’absence de maintenance persistante ne force plus le mode spectacle. L’entrée en spectacle révoque les accès administrateur ; la sortie reste soumise au déverrouillage local.

Validation dans un serveur Flask isolé sur 127.0.0.1:5067, données de sécurité temporaires : configuration avec administration verrouillée stable ; déverrouillage de session ; passage spectacle ; nouveau déverrouillage ; retour configuration. Aucune autorisation utilisateur réelle modifiée. Captures : `/private/tmp/cl-security-panel-show.png` et `/private/tmp/cl-security-panel-configuration.png`.

## 2. Nettoyages effectués

Deux surcouches JavaScript intégrées à la boucle principale : CL_SECURITY_ARM_TOGGLE et CL_SECURITY_PANEL_COMPACT_POLISH. Suppression de leurs MutationObserver : état d’armement directement issu de state.armed, demandes visibles seulement si présentes. L’ouverture explicite de la configuration n’est plus annulée par la surcouche. Expiration des feedbacks de succès également dans leur mémoire interne. Quatre affectations mortes de local_development_seen supprimées. Aucun nettoyage CSS agressif. security_http.py inchangé.

Sauvegardes ciblées : `/private/tmp/CL_SECURITY_KIT_AUDIT_20261008_155649/`.

## 3. Validation

44 tests ciblés sécurité, maintenance persistante et TLS réussis. Deux attentes obsolètes corrigées uniquement dans les tests : absence de maintenance partagée ne synchronise pas automatiquement le mode de chaque instance ; nouveau libellé iPhone validé.

Résultats finaux de la suite complète et JavaScript : voir le complément de validation à la fin du rapport. Un échec natif préexistant est identifié : mock CLMemoryDefaults sans stringForKey: dans test_simulator_dashboard_control.m ; aucune correction native hors périmètre.

## 4. Architecture Light actuelle

`launcher_light.py` force LOCAL_LIGHT avant import. `runtime_startup.py` utilise le moteur commun par défaut. `common_light_runtime.py` est l’adaptateur HTTP/état du moteur chargé depuis app.py, pas un second moteur de suivi.

| Besoin | Composants communs réutilisés |
|---|---|
| Set, scènes, sélection, lecture, reconnexion | ableton_runtime.py et fonctions app.py |
| GO, request_id, génération, confirmation, préparation suivante | go_core.py, ProfileGoConsumer |
| Durée courante et préparée, progression | scene_timing.py, fonctions de timing app.py |
| Sécurité distante, permissions, HTTPS | remote_security.py, security_http.py, remote_tls.py, remote-auth.js |
| Profil de services | app_mode.py, runtime_startup.py |
| Présentation uniquement Light | templates/light.html, static/light.css, static/light.js |

Le timing commun conserve durée déclarée dans le nom, estimation depuis clips et calcul de progression du moteur FULL. Il ne dépend pas d’un LTC externe en Light ; une estimation de clip n’est pas une mesure audio absolue. Ne pas promettre une synchronisation sample-accurate.

Consoles, Program Change, attentes/retours, backup, LTC/MTC, Arrangement et découverte multi-machines sont désactivés par capacités. Remote conservé : HTTP 5050 et HTTPS 8443 avec permissions/appairage existants ; AbletonOSC local 11000/11001. Ce profil n’est plus le premier Light strictement loopback sans remote.

Les essais du moteur commun restent partiellement validés : commandes locales et HTTPS iPhone confirmées ; scénarios manuels Live, nouveau Set, fermeture/réouverture et nouvelle autorisation/révocation doivent être revalidés sur cette voie avant release définitive. Ne pas transférer automatiquement les résultats de l’ancien runtime.

## 5. Anciens fichiers Light

light_runtime.py et light_timing.py sont encore accessibles via CL_LIGHT_ENGINE=legacy et couverts par des tests. Candidats à retrait après validation complète du moteur commun, pas à supprimer maintenant. Conserver UI, launcher, app_mode, go_core, scene_timing, ableton_runtime, common_light_runtime et tests. Corriger ultérieurement les docstrings de démarrage qui décrivent encore un runtime sans import de app.py.

## 6. Kit existant

Entrée développeur : packaging/Creer_Le_Kit_CL.app.sh → scripts/export_transport_kit.command → scripts/build_release.sh. Architecture universal2 par défaut. Builds temporaires, copies ressources, nettoyage de la copie, signature ad hoc, contrôles architecture/signature, ZIP et SHA256. Installation via Installer la Suite CL.app, rôle/configuration, désinstallation associée.

Le kit transport actuel prévoit 13 applications : CL Show Control, CL ShowCue, CL Cue Editor, CL Arrangement Builder, CL Audio Export, CL Ableton Remote, CL MIDI Network Manager, CL MIDI RTP Agent, CL MIDI & RTP Diagnostic, CL MIDI Analyzer, CL MIDI Performance Monitor, CL MTC Bridge, CL Sync Meter. CL Cue Editor correspond à la spec CL ShowCue Builder : pas besoin d’un deuxième bundle Builder identique.

Il comprend aussi AbletonOSC CL, script Arrangement Builder Live, appareils Max for Live, CL_Transport, ressources et documentation. CL_Transport exige actuellement les bibliothèques CL5/QL1. Deux dépôts frères sont nécessaires : AbletonOSC et CL_Arrangement_Builder_Live.

CL Show Backup est déclaré dans le catalogue des rôles mais n’est pas construit/copié par l’export actuel. L’installateur exige SCENE_BACKUP_HMAC_RX_VALIDATED pour ce composant : ne pas annoncer une application Backup distribuée sans receiver effectivement construit et validé.

L’archive 2.2.1 du 25 septembre comprend 11 applications ; Bridge et Sync Meter sont les compléments prévus aujourd’hui. L’export reconstruit certains outils déjà construits par build_release (Arrangement Builder, Audio Export, ShowCue/Cue Editor) : doublon de travail à rationaliser plus tard, aucun script modifié ici.

## 7. Nouveau kit FULL proposé

Conserver le catalogue complet actuel, les scripts Ableton, dispositifs Max, données de référence autorisées et docs utiles. Construire depuis un seul état source validé, avec inventaire par composant : version, commit, architecture, signature, rôle, checksum. Vérifier tous les bundles réellement produits plutôt que leur simple déclaration au catalogue. Show Backup est une porte de validation séparée. Exclure secrets, certificats privés, pairings, environnements, caches et captures. Ne pas embarquer les fichiers personnels de production par défaut.

## 8. Kit Light proposé

Minimum : CL Show Control Light.app ; AbletonOSC CL ; interface Light ; moteur commun avec profil Light ; sécurité/HTTPS et QR nécessaires au remote ; installation/désinstallation spécifiques ; guide, manifeste, versions et SHA256. Ableton Live et médias utilisateur ne sont pas redistribués. Bundle distinct com.claudio.showcontrollight.

Exclure outils consoles/MIDI/RTP, bibliothèques CL5/QL1, backups, LTC/MTC, Performance Monitor, outils réseau FULL, Arrangement et Audio Export/ffmpeg du kit minimal. Certaines dépendances FULL restent importées transitivement par app.py : absence de service démarré ne prouve pas absence dans le bundle. Audit PyInstaller gelé requis avant retrait des modules.

Attention : ShowCue desktop ouvre /show-info qui est un alias Light ; Cue Editor ouvre /show-info/builder indisponible dans ce profil. Ne pas inclure ces applications comme fonctionnalités Light opérationnelles sans extension explicitement validée. Les formats communs sont conservés dans le code, mais cela ne constitue pas une prise en charge complète Builder dans Light.

Ne pas réutiliser CL_Transport sans profil : il exige des données console. Préférer un assembleur commun avec manifestes FULL/LIGHT. Installation côte à côte possible ; exécution simultanée FULL/Light non garantie car ports 5050/8443/11001 communs. Prévoir contrôle d’occupation clair avant distribution.

## 9. Mention LSS

Clarification utilisateur : aucun composant LSS. Il s’agit de l’UI Light, moteur Ableton commun, scènes, timing, durée, préparation et remote sécurisé. Aucun nouveau système ni acronyme créé.

## 10. Versions et proposition

README et CHANGELOG annoncent 2.2.0 ; CHANGELOG date cette entrée du 25 juillet 2026, pas du 17 septembre. build_release.sh utilise 2.2.0 par défaut ; export_transport_kit.command utilise 2.2.1.

Origine vérifiée : commit ba9db5c, « Update transport packaging », 26 septembre 2026 20:55 +02, modifie le défaut 2.2.0 → 2.2.1. Artefact antérieur : Releases/CL_Audio_Controller_2.2.1_2026-09-25_16-39-13, BUILD_INFO commit df556ec79e4b52aac0c832daa6cf9f0216a6e735, construit 25 septembre 14:40:12 UTC, universal2. L’artefact précède le changement de défaut : utilisation explicite de version probable, invocation exacte non démontrée. Tags trouvés : v2.0.0 et v2.1.0 ; aucun tag 2.2.x.

Les bundles de cette archive ne sont pas homogènes : Show Control 2.2.0 ; ShowCue/Cue Editor/Audio Export 1.0.0 ; Arrangement Builder 1.2.2 ; Ableton Remote et outils MIDI 2.2.1. L’archive 2.2.1 n’implique donc pas tous les bundles en 2.2.1. Le BUILD_ID 2.0.1-identity-v1 est un marqueur d’identité/protocole à distinguer d’une version marketing.

Proposition, sans application : kits FULL et LIGHT 2.3.0, manifeste distinguant version du kit et versions des composants. Artefacts CL_Kit_Complet_2.3.0_macOS_universal2.zip et CL_Kit_Light_2.3.0_macOS_universal2.zip avec SHA256. Un tag commun v2.3.0 pour les deux profils ; éventuellement v2.3.0-rc.1 tant que les gates runtime/packaging restent ouvertes. Notes : moteur commun Light, UI dédiée, timing et remote sécurisé, panneau compact fiabilisé. Aucun numéro/tag modifié.

## 11. Fichiers touchés dans cette passe

remote_security.py ; static/security-panel.js ; static/security-panel.html ; tests/test_security_panel_network.py ; tests/test_phase2_security.py ; tests/test_development_access.py ; tests/test_remote_tls_setup.py ; ce rapport. Tous les autres changements Git sont antérieurs et conservés. Aucun changement Light, packaging ou métier supplémentaire dans cette passe.

## 12. État Git et étapes suivantes

État avant ajout de ce rapport :

```text
 M app.py
 M launcher_control.py
 M osc_transport.py
 M remote_security.py
 M static/security-panel.html
 M static/security-panel.js
 M tests/js/render_remote_fixture.py
 M tests/test_development_access.py
 M tests/test_hot_backup_sync.py
 M tests/test_network_target_independence.py
 M tests/test_osc_transport.py
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
?? docs/SHOWCUE_MOBILE_EDITOR.md
?? go_core.py
?? launcher_light.py
?? light_runtime.py
?? light_timing.py
?? packaging/Installer_CL_Autonome.command
?? runtime_startup.py
?? scene_timing.py
?? scripts/package_autonomous.py
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
```

Six exclusions historiques conservées non suivies : docs/SHOWCUE_MOBILE_EDITOR.md ; packaging/Installer_CL_Autonome.command ; scripts/package_autonomous.py ; static/marquee/marquee_off.png ; static/marquee/marquee_on.png ; static/marquee/showcue-marquee.css.

Ordre recommandé : valider cet audit ; terminer scénarios réels moteur commun et permissions ; clarifier périmètre Builder Light et conflit de ports ; harmoniser manifestes/versionnement avec accord ; build de validation et audit dépendances ; seulement ensuite autoriser commit/tag/packages définitifs. Aucun retrait legacy avant validation.

## Complément de validation finale

- Python complet : **1349 réussis, 1 ignoré, 122 sous-tests réussis, 1 échec**. Échec natif préexistant : `test_dashboard_simulator_ownership[test_simulator_dashboard_control.m]`, mock `CLMemoryDefaults` sans `stringForKey:`. Il reste hors périmètre ; la suite complète n’est donc pas entièrement verte.
- JavaScript : **27/27 suites réussies**, y compris Light et Security Panel via tests Python ciblés.
- Python ciblé sécurité : **44 réussis**.
- Syntaxe Python des fichiers sécurité/tests touchés et JavaScript du panneau : OK.
- `git diff --check` : OK.
- Serveur temporaire de validation arrêté ; aucun serveur utilisateur arrêté.
- Rapport ajouté non suivi ; autres statuts inchangés. Rien ajouté à l’index.

Logs : `/private/tmp/cl-security-kit-final-python.log`, `/private/tmp/cl-security-kit-final-js.log`, `/private/tmp/cl-security-kit-target.log`.

## Inventaire Light A/B/C et architecture cible

| Catégorie | Fichiers | Décision et dépendances |
|---|---|---|
| A | templates/light.html ; static/light.css ; static/light.js | Conserver présentation, polling, pending, clavier ; aucun moteur de durée dans l’UI |
| A | launcher_light.py ; app_mode.py ; runtime_startup.py | Entrée, capacités et sélection de moteur ; retirer seulement le choix legacy après validation |
| A | common_light_runtime.py | Adaptateur état/actions/routes, dépendant du moteur commun et sécurité ; conserver sans y dupliquer le suivi |
| A | ableton_runtime.py ; go_core.py ; scene_timing.py | Services communs, utilisés par Light ; garder le nom commun et tester FULL |
| A | app.py ; osc_transport.py | Hôte commun et OSC ; points de couplage à profiler, pas à copier |
| A | remote_security.py ; security_http.py ; remote_tls.py ; static/remote-auth.js ; static/remote-pair.html/js ; static/remote-check.html/js ; static/security-panel.html/js | Sécurité remote commune et UI de configuration, actuellement embarquées dans la spec Light |
| A | CL Show Control Light.spec ; assets/app_icons/CL_Ableton.icns | Packaging distinct, icône dérivée partagée ; compléter audit frozen avant release |
| A | tests/test_common_ableton_runtime.py ; tests/test_common_light_runtime.py ; tests/test_local_light_go.py ; tests/test_light_packaging.py ; tests/js/test_light_ui.cjs | Garder les contrats communs et UI ; séparer progressivement assertions exclusivement legacy |
| A | docs/LOCAL_LIGHT_PHASE3.md ; docs/LOCAL_LIGHT_PHASE4.md ; docs/LOCAL_LIGHT_TIMING.md | Historique de validation utile ; préciser moteur testé avant d’en tirer une garantie release |
| B | fonctions de suivi/timing encore dans app.py derrière ableton_runtime.py et scene_timing.py | Poursuivre extraction vers modules communs si nécessaire, sans réécriture ni changement d’ordre des effets FULL |
| C à terme | light_runtime.py ; light_timing.py | Secours explicitement sélectionnable, non mort aujourd’hui ; supprimer uniquement après revalidation et suppression du sélecteur legacy |
| C partielle à terme | tests/test_local_light_runtime.py ; tests/test_light_timing_selection.py | Retirer uniquement les cas propres au moteur supprimé ; transférer les contrats utiles au moteur commun |

Scripts autonomes `scripts/package_autonomous.py` et `packaging/Installer_CL_Autonome.command` : chantier existant exclu de consolidation, pas un assembleur Kit Light validé. Ne pas le supprimer ni l’intégrer par défaut. Il n’existe pas encore d’assembleur final Light équivalent à export_transport_kit.command.

```text
CL Show Control engine
(app.py + ableton_runtime.py + go_core.py + scene_timing.py + osc_transport.py)
├── profil FULL → launcher_control.py → UI FULL
│   └── consommateurs consoles / backups / services FULL
└── profil LIGHT → launcher_light.py → common_light_runtime.py
    ├── templates/light.html + static/light.css + static/light.js
    └── sécurité remote commune : security_http / remote_security / remote_tls
```

Routes d’exploitation Light : GET /, GET /status, POST /action (go, prev, next, goto, stop), ressources statiques ; /show-info alias Light. Routes communes de sécurité et remote conservées et contrôlées. Builder, consoles, backup et configuration FULL ne sont pas des routes d’exploitation Light. Pause non exposée dans ce profil.

## Catalogue précis proposé pour les deux kits 2.3.0

Versions « actuelles » ci-dessous : valeurs de source du build actuel ou archive 2.2.1 explicitement indiquée ; aucun nouveau bundle construit pendant cet audit.

| Application FULL | Rôle | Source/build | Version actuelle | Proposition | Dépendances |
|---|---|---|---|---|---|
| CL Show Control | Moteur et serveur | CL Audio Controller.spec, launcher_control.py | 2.2.0 / build 6 | 2.3.0 | Flask, pywebview Cocoa, OSC, services FULL |
| CL ShowCue | Conduite | CL ShowCue.spec | 1.0.0 / 1 | 2.3.0 | serveur Show Control, webview |
| CL Cue Editor | Builder | CL ShowCue Builder.spec | 1.0.0 / 1 | 2.3.0 | routes Builder, serveur FULL |
| CL Arrangement Builder | Préparation Live | dépôt frère CL_Arrangement_Builder_Live, Arrangement Builder Live.spec | archive : 1.2.2 | 2.3.0 édition kit, à coordonner avec dépôt frère | PySide6, Remote Script Live |
| CL Audio Export | Export audio | CL Show Audio Builder.spec | 1.0.0 / 1 | 2.3.0 | ffmpeg, UI desktop |
| CL Ableton Remote | Fenêtre télécommande | packaging/RemoteAbleton.m, build_release.sh | $VERSION : défaut 2.2.0 direct / 2.2.1 export | 2.3.0 | Cocoa, serveur |
| CL MIDI Network Manager | Configuration MIDI | tools/cl_midi_network/build.sh + build_release.sh | $VERSION | 2.3.0 | CoreMIDI, Cocoa |
| CL MIDI RTP Agent | Agent RTP | mêmes scripts, bundle agent natif | $VERSION | 2.3.0 | CoreMIDI/RTP |
| CL MIDI & RTP Diagnostic | Diagnostic | CLAudioConfigurationChecker, mêmes scripts | $VERSION | 2.3.0 | CoreMIDI, profils |
| CL MIDI Analyzer | Analyse MIDI | CLMIDIAnalyzer, mêmes scripts | $VERSION | 2.3.0 | CoreMIDI |
| CL MIDI Performance Monitor | Mesures | CLMIDIPerformanceMonitor, mêmes scripts | $VERSION | 2.3.0 | mesures natives |
| CL MTC Bridge | Bridge | tools/ableton_mtc_bridge, assemblage export_transport_kit.command | version absente du plist d’assemblage actuel | 2.3.0 | binaire bridge natif |
| CL Sync Meter | Contrôle sync | tools/ableton_mtc_bridge/build_sync_meter.command | 1.2 / build 2 | 2.3.0 | Cocoa, composants sync |
| Installer / Désinstaller la Suite CL | Installation | packaging/CLSuiteInstallerApp.m + export_transport_kit.command | $VERSION | 2.3.0 | manifestes, rôles, composants signés |

CL Show Backup exclu tant que le receiver requis n’est pas réellement construit et validé. Aucun bundle ShowCue Builder supplémentaire : son nom utilisateur est CL Cue Editor.

Kit LIGHT : une seule application d’exploitation, **CL Show Control Light**, launcher_light.py et spec dédiée, actuelle 1.0.0/build 1, proposée 2.3.0 ; installer/désinstaller Light à profiler. Remote et Security Panel sont des ressources/services de cette application, pas des utilitaires supplémentaires. Pas de ShowCue/Cue Editor autonomes dans le kit minimal actuel. Les formats communs pourront être ajoutés seulement lorsqu’une ingestion utile au profil est validée.

## Mécanisme de version et sorties

Les versions divergent parce que les specs PyInstaller contiennent des constantes indépendantes du paramètre shell $VERSION. Les wrappers natifs reçoivent ce paramètre ; Arrangement Builder vient d’un autre dépôt ; Sync Meter a ses propres constantes et Bridge n’a pas de version marketing dans le plist d’assemblage. Aucun mécanisme unique ne propage actuellement la version à tous les bundles.

Injection à revoir après accord : scripts/build_release.sh (argument 1, défaut 2.2.0 ; make_native_app injecte CFBundleShortVersionString et build 1), scripts/export_transport_kit.command (CL_AUDIO_VERSION défaut 2.2.1 ; wrappers installateur), specs PyInstaller citées ci-dessus, build Sync Meter et plist Bridge, spec du dépôt frère Arrangement Builder.

Sorties actuelles : `Releases/CL_Audio_Controller_<version>_<horodatage>/` ou CL_RELEASE_OUTPUT_ROOT ; DMG `CL_Audio_Controller_<version>.dmg`, ZIP `CL_Audio_Controller_<version>_Kit_Complet_macOS.zip`, ZIP Max `CL_Audio_Controller_<version>_Max_for_Live.zip`. Kit transport : Bureau ou CL_SUITE_EXPORT_DIR, `CL_Suite_Transport_<horodatage>_<architecture>.zip` + SHA256 ; copies iCloud optionnelles. Les deux voies utilisent des répertoires de travail temporaires.

Comparaison : 2.2.0 est le numéro documenté/default build ; 2.2.1 est un artefact réel et le défaut export actuel, sans tag/changelog associé. Aucune correspondance vérifiée entre une archive 2.2.0 et la date utilisateur du 17 septembre : ne pas l’inventer. L’état source actuel comprend les évolutions Light/sécurité et Bridge/Sync Meter non équivalentes à l’archive 2.2.1 de 11 apps.

## Convention proposée et structure Light

Version globale et CFBundleShortVersionString de chaque app distribuée : 2.3.0 pour cette édition coordonnée. CFBundleVersion : numéro de build numérique monotone propre à chaque bundle, supérieur à son dernier build distribué ; ne pas remettre arbitrairement tous les builds à 1. Un manifeste de release central alimente les specs/wrappers et verrouille les commits des dépôts frères. Les versions de protocole, données et identité restent distinctes. Vérifier les plists avant signature, puis signer et vérifier ; ne pas modifier des plists après signature.

```text
CL_Kit_Light_2.3.0_macOS_universal2/
├── Installer CL Light.app
│   └── Contents/Resources/Composants/
│       ├── Applications/CL Show Control Light.app
│       └── Ableton/Remote Scripts/AbletonOSC/
├── Désinstaller CL Light.app
├── Documentation/Installation et exploitation.md
├── RELEASE_MANIFEST.json
└── SHA256SUMS.txt
```

Noms des installateurs et structure proposés, pas générés. Aucun secret/certificat privé/pairing embarqué. Tag commun v2.3.0, ou candidat v2.3.0-rc.1 ; futures versions patch pour corrections compatibles, mineures pour fonctionnalités/profils, majeures pour ruptures explicites.

## Checklist réelle avant release et recommandations avant commit

- [ ] Traiter ou isoler explicitement l’échec mock natif ; ne pas annoncer Python entièrement vert aujourd’hui.
- [x] Syntaxe sécurité Python/JS et git diff --check ; 27 suites JS ; 44 tests sécurité ciblés.
- [x] Security Panel : show/configuration, verrouillage local, configuration sans maintenance persistante, droits repliables ; rendu connu conservé.
- [ ] Vérifier armement/désarmement et permissions depuis un iPhone réel ; approbation, révocation, erreurs HTTPS et réouverture Safari.
- [ ] Moteur commun Light : suivi lancement manuel Live, changement de Set/génération, fermeture/reconnexion, indisponibilité.
- [ ] GO, anti-doublon, sélection réelle, préparation suivante ; STOP ; test Live pause → GO (aucune action pause Light ajoutée).
- [ ] Timing courant/préparé, durée absente, clips multiples et STOP ; aucune dépendance LTC/MTC/console en Light.
- [ ] UI Light grande/petite fenêtre et remote ; clavier sans doublon, pending et génération obsolète.
- [ ] FULL : consoles CL5 canal 1/QL1 canal 2, backup, transport, ShowCue/Builder sans régression.
- [ ] Packaging : architecture universal2, signatures strictes, plists/version/build de chaque app, ressources, licences, checksum, décompression de contrôle.
- [ ] Lancer chaque app packagée et vérifier ses outils ; pas seulement tester les scripts source.
- [ ] Installer/désinstaller FULL et LIGHT côte à côte ; conflit des ports signalé proprement.
- [ ] Test machine propre, dépendances AbletonOSC et autorisations macOS ; vérifier absence de secrets et d’exigences console Light.
- [ ] Revue des fichiers à indexer avec les six exclusions historiques ; validation utilisateur avant commit/merge/tag/push/packages définitifs.

Cette continuation ne modifie que le rapport. Les sept fichiers sécurité/tests ont été modifiés dans la passe précédente décrite plus haut ; aucun nouveau changement applicatif, version, packaging, ni suppression. L’état Git reste celui de la section 12 avec le présent rapport non suivi.
