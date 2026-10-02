# Phase 1 — stabilisation du 2 octobre 2026

Périmètre : cycle de vie du launcher, retrait de l’autostart implicite du Network
Manager, migration/désinstallation des jobs connus, Scene Backup asynchrone et
identité d’exécution additive. Aucun changement des mappings MIDI, Program Change,
sessions RTP, endpoints de production, Expected/Returned, Bonjour ou HotBackup.
Aucune installation, aucun lancement d’app de production, aucun commit.

## Sauvegardes et corrections

Les fichiers préexistants concernés sont copiés avec leur arborescence sous
`backups/phase1-stabilisation-20261002-011734/`. `manifest.json` contient leurs
SHA-256 avant cette phase. Les fichiers nouveaux n’ont pas de version antérieure.

- `cleanup_launcher()` est unique et idempotent : fermeture de fenêtre, Cmd+Q
  via l’événement Cocoa `closing`, `/quit`, SIGTERM/SIGINT, sortie normale/atexit.
  L’arrêt du backend garde les preuves d’identité/token existantes. Les enfants
  suivis par Popen reçoivent TERM, une attente de 4 s, puis KILL si nécessaire.
  Le démarrage est refusé une fois le cleanup engagé.
- Le bridge MTC n’est plus détaché. Son handle est mémorisé ; un bridge externe
  trouvé par diagnostic n’est jamais adopté ni signalé. Arrêt/restart s’appliquent
  au bridge possédé uniquement. `/api/cl-mtc-bridge/status` expose `owned`.
- La création implicite du LaunchAgent moniteur est supprimée du Manager. Les
  modes `--show-control-monitor` et historique `--background-monitor` subsistent.
- Les installateurs de suite, ancien kit et kit MIDI retirent l’ancien job
  moniteur lors de la migration. Le kit MIDI ne démarre plus de moniteur permanent.
  Le désinstallateur retire les deux jobs selon les composants sélectionnés ;
  « toute la suite » inclut le lecteur RTP. Les données utilisateur restent conservées.
- Scene Backup : file bornée (64), worker seul propriétaire de socket non bloquante,
  trois copies V1 à environ 15 ms d’intervalle, destinations entrelacées, âge maximal
  de 0,5 s. Une reconfiguration/session invalide les événements antérieurs. Une
  séquence consommée peut être abandonnée : les trous sont donc normaux.
- `snapshot()` ajoute `queued`, `enqueued`, `sent_packets`, `send_errors`, `dropped`,
  `expired`, `last_scene_sent`, `worker_running`, `closed`, `config_volatile`.
  `close()/stop()` interrompt les délais, abandonne la file et attend le worker.
  Le backend enregistre `close()` à la sortie normale. Aucun ACK ni persistance.
- `runtime_identity` dans `/status` backend et `/state` launcher contient build ID,
  PID, exécutable, script, backend, origine repo/bundle, hash court et mtime du
  fichier. Métadonnées mises en cache ; le build ID historique n’est pas renuméroté.
  Le launcher expose aussi `backend_runtime_identity` lorsqu’il le reçoit.

La configuration Scene Backup reste **volatile** : enabled, destinations, show et
port doivent être réappliqués après redémarrage. Aucun changement côté receiver.

## Validation automatique

Commande obligatoire exécutée :

```sh
python3 -m py_compile app.py launcher_control.py scene_backup_udp.py runtime_identity.py
```

Les scripts modifiés passent `bash -n`. Le Manager passe une vérification native
`clang -fsyntax-only -fobjc-arc -fblocks`, sans lancement CoreMIDI ; avertissements
macOS de dépréciation préexistants.

Les tests utilisent mocks de processus/sockets et des données utilisateur
redirigées par `Path.home()` vers un dossier temporaire. Aucun HOME système n’est
changé. La transaction GO réelle est extraite sans importer le backend et testée
avec un worker dont le réseau est bloqué : le GO retourne sans attendre.

Résultats : **36 tests ciblés passent**. Suite élargie : **171 passent, 21 échecs
préexistants, 3 sous-tests passent**. Aucun nouvel échec introduit n’a été identifié.
Les 20 échecs MIDI/packaging sont reproduits sur les sources sauvegardées ; le
HTML du test UI restant est strictement identique.

Les résultats détaillés de la dernière exécution sont conservés dans
`backups/phase1-stabilisation-20261002-011734/test-results.txt`.

Les tests de texte anciens du Network Manager/packaging ont des échecs déjà
présents dans les sources sauvegardées. Le test UI serveur restant porte sur un
HTML identique avant/après. Ces zones MIDI/UI n’ont pas été corrigées dans cette phase.
Le test qui interdisait tout `.kill()` est ajusté pour autoriser uniquement
l’escalade d’un handle enfant possédé ; le backend conserve l’interdiction.

## Vérifications manuelles — après construction du build candidat

Les apps installées précédemment ne reflètent pas automatiquement les sources.
Ces commandes sont proposées, pas exécutées. À utiliser hors exploitation sur
un build candidat vérifié, avec Live Set de test et configurations copiées.
Pour les chemins ci-dessous, remplacer les apps installées par les builds validés
avant de les ouvrir. Aucun kill global ni modification de session RTP n’est requis.

### Démarrage et identité

```sh
open "/Users/mbprochris/Applications/CL Show Control.app"
ps -axo pid,ppid,command | rg 'CL Audio Controller|CL MIDI Network Assistant|CLYamahaConsoleSimulator|CLAbletonMTCBridge'
curl -fsS http://127.0.0.1:5055/state | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps({k:d.get(k) for k in ("runtime_identity","backend_runtime_identity")},indent=2))'
curl -fsS http://127.0.0.1:5050/status | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin).get("runtime_identity"),indent=2))'
```

Démarrer des simulateurs et le bridge depuis **ce launcher**. Noter les PID ; un
bridge externe préexistant reste externe et peut légitimement rester après Quitter.

### Bouton rouge, Cmd+Q, puis /quit

Fermer au bouton rouge ; attendre jusqu’à 15 s pour un arrêt normal complet.
Relancer et refaire avec Cmd+Q, puis relancer et utiliser :

```sh
curl -fsS http://127.0.0.1:5055/quit
```

Après chacun des trois essais :

```sh
ps -axo pid,ppid,command | rg 'CL Audio Controller|CL MIDI Network Assistant|CLYamahaConsoleSimulator|CLAbletonMTCBridge'
lsof -nP -iTCP:5050 -sTCP:LISTEN
lsof -nP -iTCP:5055 -sTCP:LISTEN
lsof -nP -iUDP:20809
```

Les PID possédés doivent disparaître. Si le backend refuse l’arrêt pour défaut de
preuve, consulter `/private/tmp/CL_Audio_Controller_keyboard.log` : aucun processus
étranger ne doit être tué pour libérer un port. Les outils externes sont conservés.

### Network Manager et RTP Agent

```sh
launchctl print "gui/$(id -u)/com.claudio.midi-network-monitor"
launchctl print "gui/$(id -u)/com.claudio.midi-rtp-agent"
open "/Users/mbprochris/Applications/Analyse - Réseau - MIDI/CL MIDI Network Manager.app"
```

Quitter le Manager, puis répéter les deux lectures launchctl. Après migration,
le job moniteur doit être absent ; ouvrir le Manager ne doit ni le créer ni le
charger. Le RTP Agent volontaire doit garder son état initial. Un ancien plist
n’est retiré que par l’installation/désinstallation, pas par l’app au runtime.

### Latence du GO — environnement de test uniquement

Ces commandes lancent réellement une scène dans le Live Set de test. `scene`
est 1-based ; changer 1 pour la scène témoin souhaitée. Lire la génération avant
chaque GO ; utiliser un request_id neuf pour éviter la réponse idempotente cachée.

```sh
curl -fsS -X POST http://127.0.0.1:5050/api/scene-backup -H 'Content-Type: application/json' -d '{"enabled":false}'
CL_TEST_GENERATION=$(curl -fsS http://127.0.0.1:5050/status | python3 -c 'import json,sys; print(json.load(sys.stdin)["set_generation"])')
curl -sS -w '\nGO secondes=%{time_total}\n' -X POST http://127.0.0.1:5050/action -H 'Content-Type: application/json' -d "{\"action\":\"go\",\"scene\":1,\"set_generation\":$CL_TEST_GENERATION,\"request_id\":\"$(uuidgen)\"}"

curl -fsS -X POST http://127.0.0.1:5050/api/scene-backup -H 'Content-Type: application/json' -d '{"enabled":true,"show":"TEST","port":12042,"destinations":[{"host":"127.0.0.1","enabled":true},{"host":"127.0.0.2","enabled":true}]}'
CL_TEST_GENERATION=$(curl -fsS http://127.0.0.1:5050/status | python3 -c 'import json,sys; print(json.load(sys.stdin)["set_generation"])')
curl -sS -w '\nGO secondes=%{time_total}\n' -X POST http://127.0.0.1:5050/action -H 'Content-Type: application/json' -d "{\"action\":\"go\",\"scene\":1,\"set_generation\":$CL_TEST_GENERATION,\"request_id\":\"$(uuidgen)\"}"
curl -fsS http://127.0.0.1:5050/api/scene-backup
curl -fsS -X POST http://127.0.0.1:5050/api/scene-backup -H 'Content-Type: application/json' -d '{"enabled":false}'
```

Répéter plusieurs fois off/on pour comparer la médiane : le délai PRIMARY OSC
reste dans le GO, mais la répétition backup ne doit plus ajouter 45 ms/destination.
Vérifier côté receiver les six paquets, leur déduplication et le format V1.

## Risques résiduels

- SIGKILL et crash natif brutal ne peuvent exécuter le cleanup Python.
- Un backend non prouvé ou récalcitrant est conservé et signalé dans le log ;
  les protections d’arrêt existantes ne sont pas contournées.
- UDP reste best-effort ; saturation, expiration et reconfiguration peuvent
  abandonner des événements. « Sent » signifie envoyé à la socket, pas acquitté.
- Cmd+Q réel, timings réseau et bundles reconstruits restent à valider manuellement.
- Les anciens LaunchAgents/apps déjà installés restent présents tant qu’une
  migration n’est pas exécutée ; aucune migration de production n’a été lancée.
- La configuration Scene Backup reste volatile et la compatibilité du standalone
  externe doit être validée. Les sujets RTP/Bonjour/Manager distant restent phase 2.
