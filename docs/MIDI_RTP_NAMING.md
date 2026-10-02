# Nomenclature MIDI / RTP CL — migration compatible

État au 30 septembre 2026 : code compatible canonique + legacy, migration macOS
**non exécutée**. Aucun port, IP, connexion, fichier `.mcfg`, routage Live ou
configuration de production modifié. Aucun reset ni commit.

## Table canonique et alias

| Nom canonique CL | Alias historique principal | Type / rôle |
|---|---|---|
| CL Ableton Clock IAC | Gestionnaire IAC Ableton Clock | Bus IAC : entrée Clock / transport du bridge MTC |
| CL MTC IAC | Gestionnaire IAC MTC vers Logic | Bus IAC : sortie MTC du bridge, entrée Sync Meter / Probe |
| CL Show Control IAC | Gestionnaire IAC Bus 1 | Bus IAC : observation MIDI expected du show |
| CL Show Control RTP | Réseau CL Show Control | Endpoint RTP du show, distinct du retour consoles |
| CL Console Return RTP | Réseau RTP MB Chris | Endpoint RTP de retour consoles |
| CL MIDI Return Test | Inchangé | Endpoint virtuel dédié au retour simulé |
| CL Direct RTP | Inchangé | Endpoint virtuel créé par le bridge RTP direct |

La casse est ignorée : `Réseau Rtp MB Chris` reste accepté. Les variantes anglaises
`IAC Driver Ableton Clock`, `IAC Driver MTC vers Logic`, `IAC Driver Bus 1`,
`Network CL Show Control`, `Network RTP MB Chris` sont également acceptées.

Pour les nouvelles installations, le **nom du bus IAC / nom local de session RTP**
est le nom canonique de la table. macOS peut afficher ce nom avec un préfixe :

- `Gestionnaire IAC <canonique IAC>` ou `IAC Driver <canonique IAC>` ;
- `Réseau <canonique RTP>` ou `Network <canonique RTP>`.

Ces formes canoniques préfixées sont acceptées **avant** les anciennes formes.
L'ordre de recherche est : canonique exact, canonique préfixé FR/EN, legacy FR/EN.
Si les deux générations existent, le canonique gagne, même si l'ancien nom est
encore enregistré dans une préférence. Les autres endpoints arbitraires gardent
leur nom explicite ; aucune correspondance approximative ne leur est ajoutée.

Ne pas renommer globalement « Gestionnaire IAC » ou « Réseau » pour supprimer les
préfixes : cela affecterait tous leurs ports. Le nom affiché CoreMIDI est construit
à partir du périphérique et de l'endpoint (`kMIDIPropertyDisplayName`, documenté
dans le SDK CoreMIDI). Un nom logique canonique ne garantit donc pas un libellé
visuel sans préfixe dans chaque application.

## Objets à ne pas confondre

- **Bus IAC** : port interne du pilote IAC, avec une source et une destination.
- **Session RTP locale** : objet de Configuration audio et MIDI ; son nom local
  fournit les endpoints source/destination du pilote réseau.
- **Nom CoreMIDI affiché** : libellé réellement sélectionné par Live et les outils.
  Le résolveur garde ce nom réel dans le diagnostic ; il ne renomme pas les objets.
- **Nom réseau / Bonjour** : annonce réseau de la session. Il peut différer du
  nom local et ne doit pas être changé par une table d'alias d'endpoints.
- **Peer** : correspondant distant connecté, jamais un alias de l'endpoint local.
- **CL Direct RTP / CL MIDI Return Test** : endpoints virtuels d'applications,
  pas des bus IAC à créer manuellement.

Les noms `Réseau CL MTC`, `Réseau CL Ableton Clock`, `CL MTC Remote` et
`CL Ableton Clock Remote` ne sont PAS des alias des bus IAC. Ils sont laissés
intacts. Les canaux consoles restent CL5 = 1 et QL1 = 2.

## Audit du dépôt et intégration

Définitions centralisées : `midi_endpoint_names.py` et
`tools/shared/CLMIDIEndpointNames.h`. Un test compile le résolveur Objective-C,
exécute ses cas puis compare sa table JSON à la table Python.

- Bridge MTC : entrée et sortie cherchent le canonique puis les alias.
- Sync Meter / Sync Probe : même résolution ; le Meter expose le nom réellement reçu.
- Network Dashboard : sélection expected, entrée du simulateur et retour consoles
  compatibles ; garde les protections de rôle IAC / RTP show / retour indépendant.
- Configuration Validator : compare les familles de noms d'endpoints, séparément
  dans chaque direction. Les comparaisons session/Bonjour/peer restent exactes.
- Yamaha Console Simulator / RTP Responder et RoundTripTester : les demandes de
  noms connus passent par le résolveur ; protocole et émission MIDI inchangés.
- RTP Agent / Direct Bridge : `CL Direct RTP` vient de la définition partagée,
  sans changer la création de l'endpoint, les connexions ou annonces réseau.
- Show Control Python : libellés canoniques, acceptation des états expected legacy.
  Les fixtures de tests contenant les anciens noms sont conservées pour vérifier
  la transition. Hot Backup et le transport AbletonOSC ne sont pas modifiés.
- Documentation d'installation et d'usage actualisée ; le guide est ajouté aux
  documents copiés par le build release et l'export du kit. Les installateurs
  n'écrivent aucune configuration MIDI de l'utilisateur.
- L'ancien audit Hot Backup conserve ses observations historiques, et les copies
  `.before-*` restent intactes. Aucun remplacement global dans les fichiers binaires,
  sets Live, CSV/CLF ou configurations de production.

Le fallback est journalisé une seule fois par paire de noms et par processus :
`CL MTC IAC : fallback legacy : Gestionnaire IAC MTC vers Logic`.
Une forme canonique préfixée est signalée comme « nom CoreMIDI préfixé », sans
être qualifiée de legacy. Endpoint absent : échec explicite du consommateur ou
état indisponible, jamais sélection d'un autre port au hasard.

## Audit réel macOS (lecture seule)

L'inventaire CoreMIDI a d'abord été vide dans la sandbox ; il a été refait hors
sandbox en lecture seule. La fenêtre Audio MIDI confirme les bus et sessions.

| Endpoint affiché observé | UID source | UID destination | Objet propriétaire |
|---|---:|---:|---|
| Gestionnaire IAC Ableton Clock | -238085484 | 284873017 | Bus Ableton Clock / pilote IAC |
| Gestionnaire IAC MTC vers Logic | -1501262701 | 717385612 | Bus MTC vers Logic / pilote IAC |
| Gestionnaire IAC Bus 1 | 1822181172 | 49336643 | Bus Bus 1 / pilote IAC |
| Réseau CL Show Control | 1418576320 | 812879448 | Session locale CL Show Control / pilote réseau |

`Réseau RTP MB Chris`, `CL Console Return RTP`, `CL MIDI Return Test` et
`CL Direct RTP` sont absents de cet inventaire ponctuel. L'absence d'un endpoint
virtuel ne signifie pas qu'il faut le recréer comme bus IAC.

Autres objets observés : bus IAC `CL Test Bench` ; sessions RTP `CL Ableton Clock`
et `CL MTC`. Les trois sessions RTP sont activées et montrent respectivement
les peers `CL Ableton Distant`, `CL Ableton Clock Remote`, `CL MTC Remote`.
Pour CL MTC, les détails affichent nom local et réseau `CL MTC`, port 5014,
source active `MTC vers Logic`, destination `Aucun`, peer `CL MTC Remote` connecté.
Ces valeurs n'ont pas été modifiées.

L'API historique `MIDINetworkSession.defaultSession` a retourné des champs vides
alors que la nouvelle interface macOS montre ces sessions actives. Elle n'est
pas une base sûre pour renommer automatiquement une des sessions observées.
Les propriétés IAC offrent des champs de nom de port modifiables, tandis que les
ports internes de « Réseau » sont non modifiables dans les propriétés du périphérique.
La session doit être éditée dans « Réglages de réseau MIDI », via **Nom local**.

Live, Show Control, Sync Meter et les outils MIDI étaient ouverts. Renommer le bus
MTC ou Clock avec les anciens exécutables actifs pourrait rompre leur sélection
et le routage actif de la session RTP. Les conditions de validation endpoint par
endpoint ne sont donc pas réunies : **aucun renommage n'a été tenté**, aucune
reconnexion ni modification de PRIMARY effectuée. Le résolveur mis à jour a été
exécuté en lecture seule sur la machine : il retrouve les quatre noms legacy du
tableau, dans les deux directions, avec leurs UID et les logs de fallback attendus.

## Plan de migration, un endpoint à la fois

Avant migration, hors exploitation : conserver les applications précédentes,
installer les exécutables compilés avec cette table, noter les UID et les sélections
Live ainsi que les connexions et routages actifs. Arrêter proprement la lecture
sur les deux Macs par une action opérateur. Ne pas réinitialiser MIDI Studio.

| Ordre | Ancien objet → nouveau nom local | Méthode | Vérifications / impact |
|---:|---|---|---|
| 1 | Bus IAC Ableton Clock → CL Ableton Clock IAC | Studio MIDI → Gestionnaire IAC → Ports → modifier uniquement ce nom de bus | Live PRIMARY : re-sélectionner si nécessaire la sortie Clock existante ; bridge : nouvelle source ; conserver les cases Sync/Track/Remote telles qu'elles étaient |
| 2 | Bus IAC MTC vers Logic → CL MTC IAC | Même fenêtre, uniquement ce bus | Bridge sortie et Meter/Probe entrée ; session RTP CL MTC : vérifier la Source active, la re-sélectionner si perdue ; Live concerné : vérifier son entrée MTC existante |
| 3 | Bus IAC Bus 1 → CL Show Control IAC | Même fenêtre, uniquement ce bus | Live : sorties des pistes MIDI / moniteur expected à re-sélectionner si perdues ; Show Control expected ; ne changer aucun canal ou Program Change |
| 4 | Session RTP locale CL Show Control → CL Show Control RTP | Réglages de réseau MIDI → sélectionner CL Show Control → champ Nom local seulement | CoreMIDI peut afficher Réseau CL Show Control RTP ; vérifier Live et entrée RTP du simulateur ; laisser Nom de réseau, port, IP et peer intacts |
| 5 | Session propriétaire de Réseau RTP MB Chris → CL Console Return RTP | D'abord trouver cet endpoint sur le bon Mac et identifier sa session ; ensuite modifier seulement Nom local | Retour consoles : re-sélectionner si nécessaire ; endpoint absent sur ce Mac pendant l'audit, donc aucune cible locale supposée |

Sur cette version de macOS, ouvrir les sessions par Studio MIDI → gestionnaire de
réseau, ou Fenêtre → Réglages de réseau MIDI. Ne pas éditer le périphérique global
« Réseau » et ne pas remplacer son nom par un nom de session.

Aucun des quatre objets présents ne nécessite une recréation pour modifier son
nom local via l'UI. Ne pas supprimer/recréer un bus pour le renommer : cela risque
de changer les identifiants. Si la session de retour est réellement absente,
retrouver la configuration prévue avant toute création ; cet audit n'invente
ni nouvelle session, ni port, ni peer.

Après CHAQUE étape, avant la suivante :

1. Relire l'inventaire avec `CLMIDIEndpointAudit` ci-dessous ; relever le nom réel
   et les UID source/destination. Accepter le canonique préfixé macOS.
2. Vérifier que les consommateurs de ce rôle détectent la nouvelle source ou
   destination. Aucun log « fallback legacy » pour ce rôle sur une découverte
   fraîche ; un log « nom CoreMIDI préfixé » est normal.
3. Dans Live, vérifier les ports Link/Tempo/MIDI et les sélections des pistes
   concernées. Si Live a perdu une sélection, sélectionner exactement le nouveau
   port correspondant, sans toucher aux autres cases, canaux, tempo ou EXT.
4. Vérifier le routage actif RTP concerné et son peer, puis effectuer un court
   essai opérateur Play/Stop/Locate. Vérifier aussi MTC continu et Hot Backup V1.
5. Si une sélection ou le comportement n'est pas confirmé, revenir au nom précédent
   et arrêter la migration. Ne pas passer à l'endpoint suivant.

## Rollback

Renommer uniquement le bus ou le **Nom local** de session venant d'être changé
avec son ancien nom local : `Ableton Clock`, `MTC vers Logic`, `Bus 1`,
`CL Show Control`, ou le nom local initial relevé pour le retour consoles.
Ne pas saisir « Gestionnaire IAC … » / « Réseau … » comme nom de bus : ce sont
les préfixes du nom affiché. Recontrôler UID, sélections Live, source active RTP
et réception CL. Les nouveaux outils continuent à accepter tous les aliases legacy.
Pour revenir aux anciens exécutables, remettre d'abord les anciens noms des ports.
Ne pas restaurer globalement un `.mcfg`, supprimer les endpoints, ou faire de reset Git.

## Builds et tests

Tous les builds de validation restent dans `/tmp` ; aucune application en service
n'a été remplacée ou lancée en parallèle. Le script réseau compile universal2 :

```sh
zsh tools/cl_midi_network/build.sh /tmp/cl-midi-names/network-build
clang -fobjc-arc -fblocks -arch arm64 -arch x86_64 \
  tools/ableton_mtc_bridge/CLAbletonMTCBridge.m \
  -framework Foundation -framework CoreMIDI -o /tmp/cl-midi-names/CLAbletonMTCBridge
clang -fobjc-arc -fblocks -arch arm64 -arch x86_64 \
  tools/ableton_mtc_bridge/CLSyncMeter.m \
  -framework Cocoa -framework CoreMIDI -o /tmp/cl-midi-names/CLSyncMeter
clang -fobjc-arc -fblocks -arch arm64 -arch x86_64 \
  tools/ableton_mtc_bridge/CLSyncProbe.m \
  -framework Foundation -framework CoreMIDI -o /tmp/cl-midi-names/CLSyncProbe
clang -fobjc-arc -fblocks tools/shared/CLMIDIEndpointAudit.m \
  -framework Foundation -framework CoreMIDI -o /tmp/cl-midi-names/endpoint-audit
/tmp/cl-midi-names/endpoint-audit
```

```sh
python3 -m pytest tests/test_midi_endpoint_names.py tests/test_hot_backup_sync.py \
  tests/test_live_set_generation.py tests/test_device_production_states.py \
  tests/test_configuration_checker.py -q
clang -fobjc-arc -fblocks tests/native/test_midi_endpoint_roles.m \
  -framework AppKit -framework QuartzCore -framework CoreMIDI \
  -o /tmp/cl-midi-names/test-roles
/tmp/cl-midi-names/test-roles
clang -fobjc-arc -fblocks tests/native/test_mtc_bridge.m \
  -framework Foundation -framework CoreMIDI -o /tmp/cl-midi-names/test-mtc
/tmp/cl-midi-names/test-mtc
```

Résultats ciblés : **201 tests réussis, 1 ignoré, 20 sous-tests réussis**, plus
les tests natifs des rôles Dashboard et du bridge MTC réussis. La suite comprend
les anciens noms réellement reçus par Show Control et Hot Backup V1.
Les deux suites de vérification textuelle `test_midi_network_tools.py` et
`test_midi_console_packaging.py` donnent **66 réussites et 19 échecs** ; elles ne
sont donc pas entièrement vertes. Les assertions de nomenclature ont été adaptées ;
les autres écarts de structure UI/packaging restent à examiner, sans modification
opportuniste des comportements existants. Le détail est dans
`/tmp/cl-midi-names/tests-legacy-source.log` pendant cette session.

La validation physique après renommage reste à effectuer, puisqu'aucun endpoint
n'a été renommé. Les ports canoniques ne sont pas créés artificiellement pour les tests.


## Fichiers touchés par ce chantier de nomenclature

Cette liste décrit uniquement cette intervention ; les autres modifications déjà
présentes dans le dépôt ont été conservées, sans reset ni commit.

Définitions et audit ajoutés :
- `midi_endpoint_names.py`
- `tools/shared/CLMIDIEndpointNames.h`
- `tools/shared/CLMIDIEndpointAudit.m`

Consommateurs adaptés :
- `app.py`
- `launcher_control.py`
- `tools/ableton_mtc_bridge/CLAbletonMTCBridge.m`
- `tools/ableton_mtc_bridge/CLSyncMeter.m`
- `tools/ableton_mtc_bridge/CLSyncProbe.m`
- `tools/cl_midi_network/CLMIDINetworkDashboard.m`
- `tools/cl_midi_network/CLConfigurationValidator.m`
- `tools/cl_midi_network/CLConfigurationProfile.m`
- `tools/cl_midi_network/CLMIDIRTPAgent.m`
- `tools/cl_midi_network/CLMIDIDirectBridge.m`
- `tools/cl_midi_network/CLYamahaConsoleSimulator.m`
- `tools/cl_midi_network/CLMIDIRoundTripTester.m`

Tests ajoutés ou adaptés :
- `tests/test_midi_endpoint_names.py`
- `tests/native/test_midi_endpoint_names.m`
- `tests/native/test_midi_endpoint_roles.m`
- `tests/test_midi_network_tools.py`
- `tests/test_configuration_checker.py`
- `tests/test_midi_console_packaging.py`
- `tests/test_live_set_generation.py`

Documentation et distribution :
- `docs/MIDI_RTP_NAMING.md`
- `M4L/Devices/README.md`
- `tools/ableton_mtc_bridge/CL_SYNC_METER.md`
- `packaging/INSTALLATION_NOUVEAU_MAC.txt`
- `scripts/build_release.sh`
- `scripts/export_transport_kit.command`
- `CL Audio Controller.spec`

Le build release recompile désormais le pont MTC dans son répertoire temporaire,
vérifie ses architectures et sa signature, puis transmet ce binaire à PyInstaller
via `CL_MTC_BRIDGE_BINARY`. Cela évite d'embarquer un ancien binaire du dépôt.
Un appel direct à PyInstaller doit fournir cette variable avec le chemin du pont
recompilé ; sans variable, le comportement historique du fichier spec est conservé.
La sélection du binaire est testée. Les exécutables natifs universal2 sont compilés ;
le kit complet de distribution n'a pas été reconstruit ni installé dans cette intervention.
