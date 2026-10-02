# CL Sync Meter 1.2

AppKit, macOS 11+, universal2. Réception uniquement : aucune correction envoyée,
aucun lancement de Live/Logic/bridge, aucun MIDI émis. Le bridge fonctionne sans
meter ; ses datagrammes de diagnostic sont non bloquants. Cadence QF, 25 fps,
Full Frame et logique d’offset inchangés.

## Compilation

```sh
bash tools/ableton_mtc_bridge/build.command
bash tools/ableton_mtc_bridge/build_sync_meter.command
open 'tools/ableton_mtc_bridge/build-sync-meter/CL Sync Meter.app'
```

Fermer le meter avant sa reconstruction. Redémarrer le bridge lors d’un créneau
adapté pour charger sa nouvelle télémétrie. Une instance déjà lancée conserve son
ancien protocole. CLSYNC1 n’est pas accepté par le meter 1.2 : mettre à jour les
deux composants ensemble. Fermer le probe avant le meter : UDP 20810 est exclusif.
Les builds sont signés ad-hoc, non notarisés.

## CLSYNC2

Un datagramme texte ASCII, champs positionnels séparés par des espaces :

```
CLSYNC2 seq instance_hex abs_raw bridge target offset_ms has_abs abs_fresh abs_age running fps mono
```

- `seq` : compteur croissant ; `instance_hex` : identifiant aléatoire 64 bits par démarrage.
- `abs_raw` : dernière vraie position reçue sur UDP 20809, sans offset, jamais extrapolée.
- `bridge` : currentTimeSeconds(), horloge interne pouvant continuer en free-run.
- `target` : bridge + offset, ramené dans la journée de 86400 secondes.
- `offset_ms` : offset MTC configuré, affiché séparément du delta de transport.
- `has_abs` : une position absolue a été reçue ; sinon raw=0 est absent, pas minuit.
- `abs_fresh` : résultat de absoluteTimeFresh(), expiration après une seconde.
- `abs_age` : secondes depuis réception ABS ; le meter poursuit ce vieillissement localement.
- `running` : 0 STOP / 1 PLAY ; `fps` : toujours 25.
- `mono` : secondes mach_continuous_time au départ du paquet.

Emission à environ 50 Hz sur 127.0.0.1:20810. Parser partagé `CLSyncProtocol.h`
utilisé par le meter et le probe ; validation stricte, valeurs finies et cohérence
cible/offset. Une nouvelle version sera nécessaire pour étendre les champs.
L’usage réseau nécessiterait une synchronisation des horloges : cette version
suppose le même Mac. Paquets dupliqués, retardés ou antérieurs au dernier timestamp
accepté sont ignorés, même après expiration du heartbeat.

## Etats, par priorité

1. **OFFLINE** : aucun CLSYNC2, ou heartbeat absent depuis plus de 500 ms.
2. **STOPPED** : heartbeat présent, transport STOP.
3. Sans cycle QF valide : **NO MTC** après 250 ms en PLAY ; pendant acquisition,
   **NO REF** si ABS manque, sinon **ACQUIRING**.
4. **FREE-RUN** : PLAY et MTC présent mais ABS absente ou stale.
5. **LOCKED** : ABS fraîche et mesure de transport acquise ; sinon **ACQUIRING**.

Une interruption QF >250 ms invalide MTC et les mesures. FREE-RUN n’est jamais
coloré comme LOCKED. Valeurs absentes masquées ; ABS stale explicitement marquée
et chaîne grisée. Le heartbeat seul ne prouve pas la présence d’ABS.

## Mesure et resets (corrélation QF)

MTC RX est reconstruit sur `CL MTC IAC` (alias historique : `Gestionnaire IAC MTC vers Logic`). Le décodeur garde
la convention forward nominale **+2 frames** (80 ms à 25 fps). Le bridge fige
pourtant le snapshot au QF0, tronqué à une frame ; QF7 arrive sept intervalles
plus tard. Comparer directement `raw + 80 ms` à la cible à QF7 mêlait donc
quantification (0–40 ms), phase et transport.

Instrumentation additionnelle, sans changer CLSYNC2 ni les octets MIDI :

```
CLSYNCQ2 instance_hex epoch cycle_id raw snapshot_exact snapshot_mono qf0_send qf7_send offset_ms
CLSYNCB1 instance_hex epoch mono offset_ms running
```

Le cycle_id augmente à la création du snapshot QF0, y compris pour les cycles
ensuite abandonnés. `epoch` augmente à chaque Full Frame (Start, Continue, Stop,
locate, offset). La frontière est envoyée sans attente ; si elle est perdue,
l’epoch du diagnostic impose quand même une nouvelle acquisition. Les diagnostics
sont facultatifs pour le bridge ; l’absence de diagnostics interdit seulement
une mesure fiable dans le meter. Les anciens récepteurs CLSYNC2 ignorent ces
messages distincts. Les nouveaux meter/probe nécessitent CLSYNCQ2 pour LOCKED.

Tous les temps de corrélation utilisent `mach_continuous_time`. Les timestamps
CoreMIDI (base `mach_absolute_time`) sont convertis dans cette base au callback ;
le timestamp local de réception sert de repli si le timestamp est nul ou invalide.
Le passage à la file principale ne change pas le timestamp de la mesure.

Association : cycle MIDI strictement ordonné 0..7, huit timestamps croissants,
intervalle individuel ≤30 ms, deuxième cycle cohérent après une invalidation.
Une table de huit diagnostics récents est dédupliquée par cycle_id. Le diagnostic
doit avoir la même instance, epoch, offset et timecode brut ; son QF0 et son QF7
doivent chacun précéder leur réception de 0 à 30 ms (tolérance d’horloge 0,5 ms).
Cette fenêtre reste inférieure à la durée minimale d’un cycle accepté (40 ms).
Un seul candidat est exigé ; ambiguïté = invalidation. Le cycle_id et la fin
d’émission doivent progresser. Chaque diagnostic ne peut servir qu’une fois.
Le diagnostic manquant au QF0 suivant invalide la prise ; un diagnostic arrivé
après cette échéance est rejeté. La cible CLSYNC2 projetée doit être cohérente
avec le snapshot du cycle à 5 ms près ; sinon aucune correction n’est calculée.
Ces seuils rejettent une mesure, ils ne lui ajoutent aucune constante.

Formule (secondes, différences circulaires sur 24 h) :

```
nominal_RX = raw + 2/25
phase = (snapshot_exact - raw) + (qf7_send - snapshot_mono) - 2/25
RX_aligné = nominal_RX + phase
TARGET_RX = target_CLSYNC2 + (qf7_receive - mono_CLSYNC2)
DELTA_ms = 1000 * (RX_aligné - TARGET_RX)
```

La comparaison porte sur l’instant de réception horodaté du QF7. Le timecode
reconstruit est validé contre le diagnostic avant d’être aligné. Le delta isole
le transport après retrait de la quantification/phase connue du générateur ; ce
n’est ni une mesure audio ni la preuve qu’un autre récepteur MTC corrige sa phase.
**Positif = position RX en avance, négatif = en retard.** Un retard artificiel de
3 ms donne −3 ms. L’offset configuré se trouve dans les deux positions comparées
et s’annule ; aucune correction empirique de 10 ms n’est appliquée.

Invalidation : changement d’offset/instance/transport, Full Frame (même réparti
sur plusieurs paquets), locate, perte/reprise ABS, QF >250 ms, cycle incomplet,
timestamps incohérents, diagnostic absent/ambigu. AVG/MIN/MAX/JITTER et samples
repartent de zéro. Acquisition d’au moins deux cycles complets après la frontière,
puis seuls les cycles corrélés comptent. Perte heartbeat >500 ms : OFFLINE.
Drops session compte les interruptions inattendues d’une mesure acquise ; les
changements explicites de transport/offset ne sont pas des drops. Une nouvelle
instance ou RESET STATS remet ce compteur à zéro.

Statistiques glissantes sur 125 samples ; jitter = écart-type population.
**Correction proposée uniquement si LOCKED, ABS fraîche, ≥25 samples, ≥2 secondes
depuis invalidation et jitter ≤2 ms.** Sinon « ACQUIRING / mesure insuffisante »,
copie désactivée. La copie est la seule action : aucun envoi au bridge.

Diagnostics détaillés : lancer `CLSyncProbe` avec `CL_SYNC_TRACE=1`. Les sorties
standard donnent AVG/MIN/MAX/JITTER, sample count, cycle_id, drops, durée du lock,
nombre de candidats et résidu référence/snapshot. stderr enregistre UDP, octets
MIDI et timestamps pour audit. Le probe et le meter utilisent le même moteur.

Références : [RFC 6295, compensation MTC forward](https://datatracker.ietf.org/doc/rfc6295/),
[CoreMIDI MIDITimeStamp](https://developer.apple.com/documentation/coremidi/miditimestamp).

PDC/interface et mesure audio externe restent des saisies manuelles non
persistées. Correction proposée = opposé de la moyenne, copie seule, jamais
appliquée. Les champs vides ne sont pas assimilés à zéro.

## Validation

```sh
clang -Wall -Wextra -arch arm64 tests/native/test_sync_meter.c -o /tmp/test_sync_arm
/tmp/test_sync_arm
clang -Wall -Wextra -arch x86_64 tests/native/test_sync_meter.c -o /tmp/test_sync_intel
/tmp/test_sync_intel
codesign --verify --strict 'tools/ableton_mtc_bridge/build-sync-meter/CL Sync Meter.app'
git diff --check
```

Tests déterministes : PLAY/LOCKED, perte ABS avec QF maintenus/FREE-RUN, reprise
ABS, offset +20 ms avec delta identique, NO MTC, OFFLINE, restart/compteurs,
rejet des anciens paquets, Stop/Play, wrap minuit, valeurs invalides et framing MIDI.

Procédure de validation réelle, pendant un créneau de test (résultats ci-dessous) :
1. Charger les nouveaux binaires, PLAY : FRESH et LOCKED.
2. Couper CL Absolute MTC seulement : après une seconde STALE/FREE-RUN, QF continuent.
3. Réactiver ABS : statistiques neuves puis LOCKED.
4. Passer offset de 0 à +20 ms : offset visible, cible/RX décalés, delta similaire.
5. Couper QF seulement : NO MTC après 250 ms ; arrêter le bridge : OFFLINE après 500 ms.
6. Relancer le bridge : nouvelle instance, samples/drops remis à zéro.
7. STOP/PLAY/STOP : états cohérents, pas d’avalanche de Full Frame.

Ces manipulations sont réservées aux tests explicitement demandés. Le meter lui-même reste passif.

## Régressions de corrélation

Compiler et exécuter `tests/native/test_sync_meter.c`, `test_sync_phase.c` et
`test_sync_correlation.c` avec `-Wall -Wextra -Werror -arch arm64`, puis `x86_64`.
Tests : cinq offsets × huit phases initiales, deux ordres UDP/MIDI, dix Stop/Play
et locates, Full Frame fragmenté, diagnostics perdus/retardés/dupliqués/ambigus,
absence de diagnostic, horodatages incohérents et seuil de proposition.

Simulation (retard réel 3 ms) : ancien delta −12 / −32 / −32 / −32 / −12 ms pour
0 / +100 / −100 / +20 / 0 ; nouveau delta **−3,000 ms** dans tous les cas, jitter
numérique <0,001 ms. Ces chiffres synthétiques ne sont pas présentés comme des
mesures de Live.

## Mesures réelles sur ce Mac (29 septembre 2026)

Live 12, bridge instrumenté, CoreMIDI IAC ; cinq phases de 10 s en lecture
continue, puis trois Stop/Play à offset nul. Le probe utilise le moteur partagé
avec le meter. Aucun saut systématique de 8–30 ms retrouvé :

| Offset ms | AVG ms | MIN ms | MAX ms | Jitter ms | Samples | Cycle | Drops | Lock s |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 | -0.060 | -0.167 | -0.031 | 0.016 | 117 | 120 | 0 | 9.300 |
| +100 | -0.055 | -0.112 | -0.023 | 0.016 | 119 | 246 | 0 | 9.490 |
| -100 | -0.062 | -0.117 | -0.034 | 0.016 | 120 | 373 | 0 | 9.589 |
| +20 | -0.058 | -0.135 | -0.028 | 0.016 | 121 | 499 | 0 | 9.669 |
| 0 | -0.059 | -0.097 | -0.025 | 0.013 | 116 | 619 | 0 | 9.279 |

Stop/Play : AVG -0.066 / -0.060 / -0.058 ms ; jitter 0.036 / 0.014 / 0.015 ms,
samples 44 / 40 / 44, cycles 673 / 720 / 774, drops 0. Audit de 154 paires :
retard QF0 0.027–0.102 ms, QF7 0.028–0.167 ms ; écart entre formule et opposé du
retard QF7 <0.001 ms. Les anciens chiffres rapportés ne suffisent pas à prouver
une association N/N+1 ; ce défaut n’a pas été reproduit avec ces binaires.

Une ligne peut voir zéro candidat pendant l’attente du diagnostic du nouveau
cycle : aucun nouveau sample n’est alors produit. La proposition de correction
est désactivée pendant cette attente. Les résultats ci-dessus portent sur la
dernière mesure corrélée, pas sur un cycle en attente.

Reste à reproduire manuellement les locates réels dans différentes parties du
set et une interruption physique du bus ; dix Stop/Play/locates ainsi que les
pertes/retards de diagnostics sont couverts par les tests synthétiques.
