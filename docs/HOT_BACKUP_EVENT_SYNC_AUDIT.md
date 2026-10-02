# Audit Hot Backup / Event Sync — 29 septembre 2026

Statut : faisabilité confirmée pour des commandes explicites issues de Show
Control ; origine des commandes à préciser avant implémentation du mode complet.
Aucun changement de comportement ni de configuration d'exploitation effectué.
Le constat matériel de 30–40 s sans ABS LOCATE intempestif est fourni par
l'opérateur ; il ne prouve pas à lui seul l'origine des glissements audio.

## Architecture réellement trouvée

- `launcher_control.py` gère l'application, les profils Local / Distant, l'accès
  au serveur CL (également local ou distant) et le cycle de vie du bridge.
  Les routes `/api/cl-mtc-bridge/{status,start,stop,restart}`, l'autostart et
  le widget existent. Ils ne réalisent pas une synchronisation à deux Lives.
- `ableton_targets.py`, `AbletonProfiles.active_target()` : Local et Distant
  sont deux profils alternatifs. Un seul est actif ; Distant ne signifie pas
  automatiquement « second lecteur de secours ».
- `app.py` crée un seul `OSCTransport`. Le serveur HTTP reçoit les actions
  utilisateur sur `/action`, puis commande la cible Ableton active.
- `osc_transport.py` envoie l'OSC sur UDP 11000 et reçoit sur UDP 11001 par
  défaut. Il gère une cible et une requête active, pas deux lecteurs corrélés.
- `CLAbletonMTCBridge.m` reçoit Start / Continue / Stop / Clock / SPP via
  CoreMIDI, les ABS SMPTE sur localhost UDP 20809, puis génère du MTC 25 fps
  vers « Gestionnaire IAC MTC vers Logic ». UDP 20810 reste diagnostic.
- Le routage RTP MIDI et le suivi EXT du Live distant sont ceux de la chaîne
  matérielle décrite par l'opérateur. Aucune implémentation de « CL MTC Remote »
  n'a été trouvée dans les sources du dépôt inspectées.
- Autres flux existants : HTTP CL (5050), retour LTC (UDP 63123), commandes
  auxiliaires Max (UDP 9001). Ils ne constituent pas un protocole de transport
  événementiel à deux lecteurs. Bonjour découvre des cibles ; il ne les synchronise pas.

## Commandes effectivement disponibles

Lecture du script installé localement dans
`/Users/mbprochris/Music/Ableton/User Library /Remote Scripts/AbletonOSC/abletonosc/song.py`,
de son serveur OSC et de ses constantes, en plus du code du dépôt.
La version installée sur le Mac distant n'a pas été inspectée.

| Besoin | Adresse AbletonOSC disponible | Sémantique / réserve |
|---|---|---|
| Play | `/live/song/start_playing` | Méthode exposée ; vérifier son point de départ sur la version Live utilisée |
| Continue | `/live/song/continue_playing` | Déjà employé par Show Control |
| Stop | `/live/song/stop_playing` | Déjà employé par Show Control |
| Position | `/live/song/set/current_song_time` | Valeur en beats, pas en secondes SMPTE |
| Lecture de position | `/live/song/get/current_song_time` | Retour en beats |
| État transport | `/live/song/get/is_playing` | Lecture seule dans ce script OSC |
| Locators | `/live/song/get/cue_points` | Couples nom / position en beats |
| Saut locator | `/live/song/cue_point/jump` | Index ou nom ; index préférable si noms dupliqués |
| Locator suivant / précédent | `/live/song/jump_to_next_cue`, `/live/song/jump_to_prev_cue` | Résultat dépendant du set et de la position |

Ces commandes peuvent viser l'IP du distant si AbletonOSC y est installé,
chargé et accessible. Leur disponibilité dans le script local ne vaut pas
validation d'exécution sur les deux Macs.

EXT : aucune propriété ou méthode documentée trouvée dans Song LOM pour
activer/désactiver External Sync ; aucun handler correspondant dans le script
AbletonOSC installé. Les propriétés Ableton Link ne sont pas EXT. Le script
local expose `/live/song/debug` (liste `dir(song)`), mais la présence éventuelle
d'un attribut interne ne démontrerait ni sa stabilité ni son caractère inscriptible.
Aucune automation d'interface ou simulation de touche EXT n'est recommandée.

Sources officielles consultées :
- [Song, Live Object Model](https://docs.cycling74.com/apiref/lom/song/)
- [AbletonOSC, SongHandler](https://github.com/ideoforms/AbletonOSC/blob/master/abletonosc/song.py)
- [AbletonOSC, OSCServer](https://github.com/ideoforms/AbletonOSC/blob/master/abletonosc/osc_server.py)

## Architecture recommandée

Conserver CONTINUOUS MTC comme mode par défaut et fallback. Ajouter HOT BACKUP
comme mode explicitement armé à l'arrêt, avec EXT désactivé manuellement sur le
distant et sans synchronisation Link concurrente. Le choix de mode dans Show
Control ne doit pas prétendre avoir modifié ou vérifié EXT automatiquement.
Le bridge et son diagnostic peuvent rester actifs : le distant libre ne doit
pas consommer le MTC comme horloge. Arrêter simplement les Quarter Frames
après GO en laissant EXT actif n'est pas une architecture de lecture libre fiable.

Un contrôleur d'événements dans le serveur CL, utilisant deux cibles explicites :

1. PREPARE / NEXT : locator absolu en beats sur les deux lecteurs arrêtés,
   contrôle de position, mémorisation de l'index préparé.
2. GO : émission rapprochée aux deux cibles, sans attendre la confirmation
   du principal avant d'envoyer au distant ; contrôle des deux résultats ensuite.
3. PLAY : aucune écriture périodique de position, tempo, vitesse ou vue.
   Une mesure en lecture seule peut informer l'opérateur, jamais corriger la dérive.
4. STOP : commande indépendante vers les deux cibles, y compris si le principal
   ne répond plus. Préparation du prochain index ensuite sur action explicite.
5. LOCATE explicite en lecture : un événement de repositionnement vers le distant,
   distinct de toute comparaison des positions courantes.
6. Perte du principal : aucune commande Stop induite par un timeout ; le distant
   continue. Aucun replay automatique d'un ancien GO/Stop après reconnexion.

Précondition : même Arrangement, mêmes locators et même carte de tempo sur les
deux machines. Une multiplication SMPTE × tempo courant / 60 serait incorrecte
en présence de changements de tempo. Transporter les beats de l'événement original.
Une table locator nom/index validée peut servir de correspondance entre sets.

La transaction actuelle `execute_arrangement_marker_go()` reprend avant de
repositionner parce que Continue peut restaurer une position de pause mémorisée.
Elle doit rester inchangée en MTC continu. Le mode événementiel devra valider
sur les deux Lives la séquence Continue puis position, éventuellement regroupée
dans un bundle OSC. Un bundle ne rend pas le départ de deux Macs simultané et
ne constitue pas un accusé de réception. Le risque de bref départ à l'ancienne
position doit être vérifié matériellement avant usage audio.

## Points nécessitant une décision ou une validation

### Origine des événements

Si GO / STOP / NEXT / LOCATE passent par Show Control, leur intention est connue.
Ils peuvent être dupliqués précisément dans leurs handlers, sans copier les
commandes de fond ni modifier les routines Program Change.

Si les mêmes actions doivent être suivies depuis l'interface Live, un contrôleur
externe ou une Liobox, ces événements ne traversent pas nécessairement `/action`.
Le flux ABS existant ne transporte ni beats, ni identifiant de commande, ni
origine du saut. Son erreur accumulée par rapport à une horloge locale ne peut
pas devenir un événement de locate : cela réintroduirait des corrections de dérive.
Il faut alors une source complémentaire : observation de transitions transport
et détection des discontinuités du principal en beats, tenant compte du tempo,
des boucles et des trous de télémétrie, ou événements explicitement émis par le
contrôleur d'origine. L'API de position seule n'identifie pas l'intention utilisateur.
Le choix entre ces deux périmètres a été demandé avant d'implémenter.

### Retours OSC et robustesse

Le script AbletonOSC installé renvoie vers l'IP du demandeur au port fixe 11001,
et dirige les notifications vers le dernier client. Ouvrir un second transport
sur 11002 ne suffit donc pas. De plus, `_receive()` corrèle aujourd'hui l'adresse
OSC et les arguments sans filtrer l'IP de la cible pour la requête active.
Deux réponses de Live pourraient être attribuées au mauvais lecteur.

Prévoir un seul récepteur local avec routage par source vers deux états séparés,
ou un relais explicitement installé côté distant. Ne pas détourner les retours
existants par un second client concurrent. Dédupliquer les événements, distinguer
« envoyé » de « confirmé », rejeter les commandes obsolètes et les changements de
mode pendant Play. UDP peut perdre un GO : ne pas le réémettre aveuglément sans
état et bornage temporel. Le principal doit rester utilisable si le secours est absent.

### Passivité et périmètre

`SCAN_PLAYING_SCENE_FROM_TRACKS = False` est présent. `show_session_view()` est
défini mais aucun appel n'a été trouvé. Des écritures `selected_scene` existent
encore dans `select_scene()` et le GO Session explicite : constat d'audit, pas
ajout de ce travail. Le nouveau mode n'en ajoutera pas. Une activation de mode,
un refresh, une découverte ou un reconnect ne doivent pas déclencher Play/Locate.

## Fichiers envisagés, pas encore modifiés

- `hot_backup_sync.py` (nouveau) : état, événements, cibles et confirmations.
- `osc_transport.py` : séparation des réponses par source, sans casser la cible unique.
- `app.py` : raccordements explicites Arrangement GO / STOP / NEXT / LOCATE,
  routes de configuration et diagnostic du mode ; pas de mirroring global de `send()`.
- `launcher_control.py` : choix discret et statut, réutilisation du widget et du
  cycle de vie existants. Afficher clairement l'exigence EXT OFF pour Hot Backup.
- Tests dédiés et documentation ; règles de packaging à contrôler selon les imports.
- Si le périmètre inclut des actions directes Live : source de télémétrie/événements
  supplémentaire à définir avant de modifier le device Max ou AbletonOSC.

## Vérifications réalisées

28 tests existants réussis, sans lancement de Live ni du bridge :

```sh
python3 -m unittest discover -s tests -p test_ableton_targets.py   # 12
python3 -m unittest discover -s tests -p test_osc_transport.py     # 13
python3 -m unittest discover -s tests -p test_mtc_bridge_control.py # 3
```

Aucun nouveau mode implémenté à ce stade ; ces tests valident uniquement la base
existante. Aucun build nécessaire pour cet audit documentaire. Pour reconstruire
le bridge actuel, hors exploitation : `bash tools/ableton_mtc_bridge/build.command`.

Tests à ajouter lors de l'implémentation : mode inactif totalement passif ;
positions en beats ; réponses interverties entre sources ; GO rapprochés et
confirmés indépendamment ; Stop du distant après panne du principal ; NEXT ;
locate explicite unique ; quatre minutes sans écriture périodique ; perte de
paquets, doublons et reconnexion ; retour au mode continu ; aucun double bridge.

## Protocole matériel prévu

1. Deux copies identiques du set, tempos et locators vérifiés. Choisir un locator
   correspondant à 02:10:00 via ses beats, pas une conversion au tempo courant.
2. Sur le distant, couper EXT manuellement et exclure une autre synchronisation
   externe. Tester Stop / locate / Continue OSC à faible niveau avant exploitation.
3. PREPARE : deux positions confirmées ; GO : mesurer l'écart réel des départs.
   Vérifier l'absence de son à l'ancienne position pendant la reprise.
4. Lire quatre minutes ; vérifier zéro correction de position/vitesse et écouter
   les glissements. Mesurer l'écart final et fixer la tolérance acceptable au spectacle.
5. Simuler la perte du principal : le distant continue ; basculer l'audio.
   Tester STOP vers le distant même lorsque le principal est injoignable.
6. Reconnecter : aucune vieille commande rejouée. STOP / NEXT / GO suivant.
7. Tester un vrai locate en lecture, puis les actions directes dans Live si elles
   font partie du périmètre retenu. Tester aussi latence/perte réseau et boucles.
8. À l'arrêt, revenir à CONTINUOUS MTC, réactiver EXT manuellement et vérifier
   la chaîne actuelle avec un seul bridge. Ne pas changer le mode en lecture.

Seul fichier ajouté par cet audit : `docs/HOT_BACKUP_EVENT_SYNC_AUDIT.md`.
Aucun reset, commit, modification de production ou commande envoyée à Live.
