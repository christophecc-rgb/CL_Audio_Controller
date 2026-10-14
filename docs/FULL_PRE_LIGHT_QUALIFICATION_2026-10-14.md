# Qualification du socle FULL avant Light — 14 octobre 2026

## Périmètre et historique

Branche locale : `consolidation/full-pre-light`, créée depuis
`022cc3ad4e49ea762a06aa5daebe0c2b6845255b`.

- `main` / `origin/main` : `25388e910d2003c7df8c7a67e9e4dc1ec953c4d6`.
- `feature/local-light` / `origin/feature/local-light` :
  `1ae743415465ea134f8032ff382fb69d1385bb9e`.
- `main` est ancêtre de `022cc3a` : 67 commits supplémentaires, aucun merge.
- Le parent direct de `1ae7434` est `022cc3a`, également référencé par
  `feature/ableton-mtc-bridge`.
- Aucun des modules launcher_light, light_runtime, common_light_runtime,
  light_timing, ableton_runtime, app_mode, go_core, runtime_startup, scene_timing,
  ni l'interface ou le kit Light n'est suivi à `022cc3a`.
- Les fonctions de suivi, GO et timing FULL restent dans app.py. Le mode
  autonome antérieur n'est pas le produit Light.

Aucun changement de main, de feature/local-light ou de l'historique existant.
Aucun push, build de distribution, installateur ni commande vers du matériel.
Le commit de consolidation ajoute seulement du nettoyage de suivi Git,
des corrections de fixtures de test et ce rapport.

## Audit des artefacts

Les PID et sauvegardes ci-dessous ont été introduits par `31209eb` ; les trois
exécutables par `c8756a6`. L'inspection des chemins modifiés dans les 67 commits
n'a pas trouvé de bytecode, caches pytest/Finder ou archives ZIP/DMG/PKG dans
ces catégories de pollution. L'histoire n'est pas réécrite.

Retirés du suivi Git avec `git rm --cached`, **copies locales conservées et
comparées octet pour octet avec 022cc3a** :

- `.run/app.py.pid`
- `.run/launcher_control.py.pid`
- `.run/show_audio_builder_desktop.py.pid`
- `.run/showcue_builder_desktop.py.pid`
- `.run/showcue_desktop.py.pid`
- `osc_transport.py.backup-osc-meter-20260913-024040`
- `templates/index.html.backup-osc-meter-20260913-024059`
- `tools/cl_midi_network/CLMIDINetworkDashboard`
- `tools/cl_midi_network/CLMIDINetworkDashboard.arm64`
- `tools/cl_midi_network/CLMIDINetworkDashboard.x86_64`

Les scripts de packaging recompilent le dashboard dans leurs dossiers de
construction depuis CLMIDINetworkDashboard.m et les autres sources. Aucun
consommateur opérationnel des trois copies à la racine des sources n'a été
trouvé. Les sauvegardes datées n'ont pas de référence utile dans le code actif.
Ajout à .gitignore de /.run/, du motif daté backup-osc-meter et des trois chemins
d'exécutables précis. Aucun autre binaire ou document n'est retiré.

Conservés volontairement : devices AMXD/Max, icônes, fixtures ShowCue,
bibliothèques consoles, JSON et autres données de production, captures et
preuves de validation. Les instantanés docs/validated-local-midi-2026-09-30
contiennent des données propres au Mac : documents historiques, pas une
dépendance runtime démontrée. .codex/environments/environment.toml ne contient
qu'un nom de projet et un script de setup vide, sans chemin utilisateur.
Les configurations actives inspectées ne présentent pas de chemin absolu
/Users dans config, CL_Transport/manifest.json ou cette configuration Codex.
Les chemins vers les dépôts voisins dans le build restent des prérequis de
construction à documenter, pas des fichiers à supprimer.

## Corrections limitées aux tests

- tests/test_hot_backup_sync.py : le test de configuration écrit maintenant
  ses préférences dans tmp_path, plutôt que dans les réglages du Mac.
- tests/test_remote_tls_setup.py : le test du port occupé réserve lui-même
  un port éphémère et conserve le socket ; évite la course entre la recherche
  d'un port libre et sa réservation. La condition testée reste un vrai port occupé.
- tests/js/test_showcue_mobile_conduite.js : querySelector ajouté au faux DOM
  pour permettre au code de détecter normalement l'absence de grille dans la fixture.
- tests/js/test_showcue_editor_consultation.js : assertion dépassée de cinq
  colonnes remplacée par la vérification des six intitulés de l'interface existante.

Aucun changement de code fonctionnel MIDI, Program Change, RTP, Ableton,
ShowCue, Arrangement, backup ou export audio.

## Tests et vérifications

Passe Python complète finale : **1229 réussis, 0 échec, 1 ignoré,
122 sous-tests réussis**, en 76,82 secondes.

```sh
CL_SECURITY_DIRECTORY=/private/tmp/cl-full-pre-light-security \
PYTHONDONTWRITEBYTECODE=1 .venv/bin/python -m pytest -q \
  -p no:cacheprovider --basetemp=/private/tmp/cl-full-pre-light-qualified tests
```

Les tests utilisant sockets loopback et CFMessagePort ont nécessité l'exécution
hors restrictions du sandbox. Première passe restreinte : 1207 réussis,
3 échecs, 19 erreurs de setup, 1 ignoré ; les restrictions de ports et la
fixture Hot Backup expliquent cette passe. Passe complète suivante : 1228
réussis, 1 échec intermittent de réservation de port, 1 ignoré ; le test
isolé passe, puis sa réservation est rendue atomique et la passe finale réussit.

Tous les fichiers tests/js/test_*.cjs et test_*.js ont été exécutés :
**29 fichiers/suites réussis**. La passe globale donnait 28 réussis et un
échec d'assertion de colonnes dans test_showcue_editor_consultation.js ; après
actualisation de cette seule assertion, ses deux tests passent aussi.
Playwright fourni par le runtime et Chrome installé servent aux tests navigateur,
avec données simulées et routes interceptées, sans serveur de production.

Contrôle AST de 175 fichiers Python/spec et syntaxe de 22 scripts shell :
aucune erreur. git diff --check et git diff --cached --check réussis.
Logs de qualification sous /private/tmp/cl-full-pre-light-*.log/json.

La suite couvre notamment :

| Domaine FULL | Couverture disponible exécutée |
| --- | --- |
| MIDI, retours et RTP | test_midi_network_tools, test_midi_event, test_command_layer, test_midi_endpoint_names, tests natifs et JS midi_return_visual |
| Profils et bibliothèques | test_device_profiles, test_device_production_states, test_console_title_library, test_dynamic_console_libraries |
| Arrangement après pause | test_arrangement_go_transaction |
| Serveur / cible Ableton | test_network_target_independence, test_ableton_targets, test_paradis_network |
| Scènes passives / générations | test_passive_scene_listeners, test_live_set_generation, test_remote_passive_feedback |
| ShowCue et sessions | test_show_cues, test_showcue_session_restoration, test_showcue_portable_roundtrip et tests JS sessions/saves/exports |
| CSV/XLSX et Builder | test_builder_import_compatibility, test_showcue_builder et tests JS Builder |
| Mobile et permissions | test_showcue_permissions, tests JS mobile_conduite, mobile_editor et remote_auth_showcue |
| Hot Backup / OSC | test_hot_backup_sync, test_phase2_backup, test_scene_backup_udp, test_osc_transport |
| MTC et synchronisation | test_mtc_bridge_control et tests natifs MTC/sync |
| Export audio | ensemble test_show_audio_* |

## Anomalie de connexion existante, non corrigée

À 022cc3a, app.py:3272 définit refresh_live_set_identity. Après une première
réponse file_path et une réponse name, l'absence de la seconde confirmation
file_path mène au retour None vers app.py:3327. refresh_names_and_transport,
défini à app.py:3871, retourne alors False avant la sonde de transport et sans
appeler set_connected_locked(False).

Reproduction isolée en exécutant uniquement les fonctions extraites par AST,
avec état prêt, génération 7, connected=True et réponses OSC simulées :

```text
file_path -> ('test.als',)
name      -> ('Test',)
file_path -> None
résultat : refresh=False, connected=True, mises à jour connexion=0
```

La fonction query/_query_with_query_lock_held ne corrige pas cet état lors de ce
timeout. L'anomalie est donc antérieure à Light. Aucun Live réel n'a été fermé
pour cette vérification, et aucune correction fonctionnelle n'est introduite.

## Conclusion et suite proposée

Le socle est propre dans Git et qualifié par les tests disponibles sans matériel.
Il peut raisonnablement servir de nouvelle base de développement de main,
après examen humain. Il n'est pas déclaré validé pour l'exploitation physique :
déconnexion Ableton ci-dessus, consoles/RTP/MTC réels, installation Mac vierge,
build et distribution restent à qualifier. Les améliorations du commit 1ae7434
(export, sécurité, release et moteur commun) ne sont pas incluses.

Après validation seulement, et si main n'a pas changé :

```sh
git switch main
git merge --ff-only consolidation/full-pre-light
```

Cette opération est possible puisque le nouveau commit de nettoyage descend
de 022cc3a, lui-même descendant de main. Aucun cherry-pick ni réécriture
n'est nécessaire. Le push reste une décision ultérieure distincte.
