# Light — moteur commun, phase 3

La voie principale est désormais `launcher_light.py` → `runtime_startup.run_light_entry()` → `common_light_runtime.run_light()`.
Lancer `.venv/bin/python launcher_light.py` (fenêtre native), ou ajouter `--serve` (serveur seul).
`CL_LIGHT_ENGINE=legacy` conserve explicitement l'ancien `LightRuntime` comme filet de sécurité. Aucun de ses fichiers n'a été supprimé ni développé.

## Composition

Un contexte interne de capacités permet de charger le module hôte du moteur existant sous une identité distincte. FULL conserve ses capacités par défaut. L'hôte Light possède son état, son transport et ses verrous ; ce n'est pas un second algorithme Ableton.

Le module hôte conserve encore des imports FULL : cette phase empêche leurs services d'être construits ou démarrés, elle ne termine pas l'allègement de tous les imports. L'extraction de ces imports reste possible ultérieurement, après validation.

Deux workers permanents : réponse OSC loopback et suivi Ableton commun. Les travaux temporaires sont ceux du moteur commun : bootstrap, abonnements aux pistes et résolution des durées courante/préparée.

Services absents : objet bibliothèque console, client MIDI Monitor, HotBackup, SceneBackupUDP, BackupSceneFollow, listeners LTC/MIDI expected, publication Bonjour expected, bridge MTC, RTP, rafraîchissement Arrangement et découverte console. La configuration de consoles n'est pas chargée ; la cible Ableton est forcée à 127.0.0.1, ports 11000/11001.

La fermeture invalide la génération et les requêtes en vol, annule le bootstrap, retire les abonnements, ferme OSC/TLS et attend les deux workers.

## API

`/status` utilise exclusivement `AbletonRuntime.light_snapshot(scene_timing)`, jamais `state_snapshot_locked()` ni `LightRuntime`.

Champs : mode, set_available, set_generation, ableton_available, state, error, current_scene/current_scene_name, prepared_scene/prepared_scene_name, next_scene/next_scene_name, is_playing, is_paused, allowed_actions, current_duration_seconds, current_position_seconds, current_remaining_seconds, prepared_duration_seconds.

Indices internes zéro-based ; le numéro `scene` envoyé par l'interface est un-based. Les durées inconnues sont null. En déconnexion, les scènes et durées sont masquées, les actions désactivées. Après reconnexion, l'identité du Set reste vérifiée par le moteur commun.

| Action | Chemin |
|---|---|
| go | create_common_light_controller → execute_go_core + ProfileGoConsumer(timing uniquement) |
| prev/next/goto | préparation dans l'état partagé, durée via SceneTimingAPI, aucun lancement ni sélection Live anticipée |
| stop | commande OSC existante stop_playing + confirmation par get/is_playing ; pas de console/backup |

Toute action valide la génération. GO exige request_id et conserve le cache anti-doublon du cœur partagé. Les réponses obsolètes restent HTTP 409.

## Timing

La durée déclarée du nom reste prioritaire, sinon les fonctions FULL existantes résolvent les clips. Le restant est actualisé depuis la deadline commune et l'écoulé est durée moins restant. Aucun polling de light_timing n'est utilisé sur la nouvelle voie. La durée préparée est ajoutée à l'UI existante.

Limite conservée du moteur FULL : lorsque l'abonnement hydrate une scène déjà en lecture au démarrage sans instant de départ connu, une durée peut être connue alors que l'écoulé/restant restent indisponibles. Aucune position n'est inventée.

## Remote

Même `attach_security`, RemoteSecurity, RemoteTLS et remote-auth.js que FULL. HTTP écoute 5050 ; le TLS existant n'est restauré que si configuré explicitement. Le pairing exige HTTPS, les signatures/permissions/armement/révocation sont inchangés. Le moteur Ableton reste loopback.

Routes : `/`, `/status`, `/action`, ressources `/static/`, routes d'administration/appairage `/security/` et `/remote/`. `/show-info` est un alias de l'UI Light pour les liens de lecture existants ; aucune route ShowCue/Builder FULL n'est activée. Autres routes FULL refusées.

L'administration de sécurité réutilise son panneau existant ; les APIs backup/console restent indisponibles, même si ce panneau générique mentionne certains outils FULL.

## Packaging

La spec Light est préparée pour embarquer l'hôte commun et les ressources d'appairage/sécurité. Aucun build n'a été exécuté ; l'application déjà construite/installée reste l'ancienne jusqu'à une reconstruction autorisée. Le code hôte importe encore certains modules FULL, qui resteront donc dans un futur bundle à ce stade, sans démarrer leurs services.

## Essai réel

Démarrage de développement connecté au Set SHOW CASSIS : 36 scènes, génération 1, scène préparée index 31, durée préparée 709 secondes. Interface et statut HTTP 200. Seulement CL Light OSC et CL Light Ableton présents ; cinq objets FULL contrôlés étaient absents. Fermeture des workers confirmée.

Aucune scène n'a été lancée ou arrêtée pendant cet essai réel. GO/navigation/STOP et remote sont validés par les tests automatisés ; un essai iPhone HTTPS réel reste à effectuer après reconstruction autorisée.

## Validation finale

- Tests ciblés : 115 réussites.
- Python complet : 1341 réussites, 1 ignoré, 122 sous-tests réussis, 1 échec.
- Échec préexistant : `test_simulator_dashboard_ownership[test_simulator_dashboard_control.m]` (simulateur natif macOS, exception « Owner opens control port »). Le simulateur et sa logique n'ont pas été modifiés.
- JavaScript : 27/27 suites réussies. Les quatre tests navigateur utilisent le Playwright fourni avec l'environnement et Chrome existant ; aucune dépendance installée.
- Syntaxe Python/JavaScript et `git diff --check` : OK.
- Les fixtures de startup FULL incluent maintenant explicitement ses capacités. Le test HotBackup écrit sa préférence dans son dossier temporaire plutôt que dans les préférences utilisateur.
- Comparaison ancien/nouveau : GO et anti-doublon, préparation, STOP, état manuel, changement de génération, déconnexion/reconnexion. La nouvelle projection ajoute la durée préparée et masque immédiatement les valeurs invalides lors d'une déconnexion.

## Fichiers de cette phase

Modifiés :

- `app.py` — capacités de l'hôte et barrières de construction/publication des services FULL.
- `runtime_startup.py` — voie principale commune et bascule legacy explicite.
- `ableton_runtime.py` — projection Light, durées invalidées quand indisponible, nom suivant/erreur simple.
- `templates/light.html`, `static/light.js` — authentification commune et durée préparée ; visuel conservé.
- `CL Show Control Light.spec` — dépendances et ressources communes nécessaires pour une future build.
- `tests/test_common_ableton_runtime.py`, `tests/test_local_light_runtime.py`, `tests/test_light_packaging.py`, `tests/js/test_light_ui.cjs` — contrats et fixtures actualisés.
- `tests/test_network_target_independence.py`, `tests/test_osc_transport.py`, `tests/test_hot_backup_sync.py` — fixtures ciblées de démarrage conditionnel et isolation des préférences.

Créés : `common_light_runtime.py`, `tests/test_common_light_runtime.py`, ce rapport.

Sauvegarde préalable : `/private/tmp/CL_LIGHT_COMMON_ENGINE_PHASE3_20261008_01/`.
Les modifications préexistantes, `LightRuntime`, les exclusions non suivies et les fichiers de production sont conservés. Aucun staging, commit, push, build ou installation.
