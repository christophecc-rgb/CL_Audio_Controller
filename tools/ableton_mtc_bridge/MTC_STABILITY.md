# Stabilité MTC pour hot backup

Le bridge existant reste l'unique générateur MTC. Show Control, son autostart,
son widget et ses routes ne changent pas. Aucun changement des canaux
CL5 (1) / QL1 (2), du Program Change, des données de production ou du contrôle Live.

## Référence et confirmations

- Start / Continue verrouillent la dernière ABS reçue si elle a moins de 1 s.
- Sans ABS fraîche, Continue utilise la position de secours (SPP ou position
  arrêtée). Start conserve la sémantique FA existante : départ à zéro.
- En lecture, la position avance avec `monotonicSeconds()`, indépendamment
  des variations MIDI Clock et Live API. Clock reste utile au tempo du fallback SPP.
- Écart ABS inférieur à 200 ms : aucune correction.
- Entre 200 et 500 ms inclus : au moins 6 mesures cohérentes sur au moins 200 ms.
- Au-delà de 500 ms : au moins 2 mesures cohérentes séparées d'au moins 30 ms,
  soit normalement une confirmation dès le prochain paquet Max, environ 40 ms.
  Ce court délai est volontaire : un locate sur un seul paquet serait incompatible
  avec la protection contre un échantillon bruité demandée.
- Cohérence : même signe, même catégorie, écart à la première mesure du candidat
  <=120 ms, intervalle entre mesures <=200 ms. Sinon la confirmation recommence.
  Un retour sous 200 ms annule le candidat. Stop et Play le réinitialisent aussi.
- Les différences sont circulaires sur 24 h pour éviter un faux locate à minuit.
- Une correction confirmée envoie un Full Frame et recommence le cycle QF à 0.
  Les petites dérives ne changent ni la référence ni le cycle QF.
- SPP ne remplace jamais une ABS fraîche. Un SPP de secours identique à la
  position courante (à 20 ms près) ne renvoie pas de Full Frame.
- À l'arrêt, les ABS continuent à fournir les locates, comme auparavant.
  Un Stop répété ne renvoie pas de Full Frame.
- Le changement explicite d'offset conserve son Full Frame existant.

CoreMIDI copie ses données vers la file principale : transport, UDP et timer
partagent ainsi une seule file. Le timer reste à 10 ms, tolérance 200 µs,
et les QF ne partent qu'en lecture. Cela ne garantit pas une cadence temps réel
sous surcharge macOS : sa régularité effective se mesure sur les deux Macs.
Les paquets diagnostic CLSYNC2, CLSYNCB1, CLSYNCQ2 sur UDP 20810 sont conservés.
Les logs de dérive ignorée sont limités à un toutes les 5 s ; les décisions de
transport / locate restent visibles. La sortie est vidée ligne par ligne.

## Build et tests (depuis la racine du dépôt, macOS)

Compilation de validation, sans remplacer le binaire utilisé par Show Control :

```sh
mkdir -p /tmp/cl-mtc-stability
clang -fobjc-arc -fblocks -arch arm64 -arch x86_64 \
  -mmacosx-version-min=11.0 tools/ableton_mtc_bridge/CLAbletonMTCBridge.m \
  -framework Foundation -framework CoreMIDI \
  -o /tmp/cl-mtc-stability/CLAbletonMTCBridge
codesign --force --sign - /tmp/cl-mtc-stability/CLAbletonMTCBridge
codesign --verify --strict /tmp/cl-mtc-stability/CLAbletonMTCBridge
lipo -archs /tmp/cl-mtc-stability/CLAbletonMTCBridge
```

Build de mise en place dans le dépôt (à faire hors exploitation) :

```sh
bash tools/ableton_mtc_bridge/build.command
```

Tests sans lancer de bridge ni envoyer de MIDI :

```sh
clang -fobjc-arc -fblocks tests/native/test_mtc_bridge.m \
  -framework Foundation -framework CoreMIDI -o /tmp/cl-mtc-stability/test_mtc_bridge
/tmp/cl-mtc-stability/test_mtc_bridge
python3 -m unittest discover -s tests -p test_mtc_bridge_control.py
python3 -m unittest discover -s tests -p test_remote_passive_feedback.py
```

Le test natif utilise les vrais handlers et le vrai encodeur QF avec une horloge
simulée et une capture des sorties. Il vérifie les confirmations, les transitoires,
les locates avant/arrière, la reprise, le fallback, minuit, 800 QF consécutifs sans
Full Frame parasite et aucun QF à l'arrêt. Il ne mesure pas le jitter physique.
Les tests Show Control exécutent les fonctions existantes avec processus simulés :
bridge déjà présent, arrêt SIGTERM puis relance unique, arrêt échoué sans doublon.
Ils ne lancent pas l'autostart de l'application.

## Protocole réel avec les deux Macs

1. Hors exploitation, utiliser le même set et les mêmes fichiers audio sur les
   deux Macs. Sur le principal : CL Absolute MTC actif, metro 40, UDP 20809.
   Sur le distant : CL MTC Remote, Ableton EXT / MIDI Timecode / 25 fps.
   Conserver le routage IAC puis RTP validé. Noter la version du build et l'offset.
2. Arrêter le bridge depuis Show Control, compiler avec `build.command`, puis
   Relancer. Vérifier un seul PID avec `pgrep -x CLAbletonMTCBridge`, ainsi que
   l'état du widget. Ne pas lancer le binaire de test en parallèle.
3. Ouvrir CL Sync Meter et suivre
   `tail -f /tmp/CL_Ableton_MTC_Bridge.log`. Vérifier que les mesures UDP 20810
   continuent et que les cycles QF sont observés en lecture.
4. Se placer à 02:00:09:04 à l'arrêt, puis Play : vérifier ABS LOCK, START ou
   CONTINUE [ABS], et la position du distant. Stop puis reprise : les deux
   transports doivent suivre ; aucun QF à l'arrêt, pas de rafale de Stop.
5. Laisser jouer au moins 15 minutes, avec charge représentative. Relever la
   dispersion des intervalles QF, l'écart entre positions et les corrections.
   Les petites variations ne doivent produire aucun ABS LOCATE ni Full Frame.
   Comparer le résultat au build précédent dans les mêmes conditions.
6. Faire plusieurs locates avant et arrière, notamment -9,144 s et -4,703 s.
   Vérifier une seule correction confirmée par saut, normalement au paquet
   suivant (~40 ms), puis une progression stable. Tester aussi une boucle.
7. Désactiver CL Absolute MTC, attendre plus d'une seconde, puis faire un locate
   SPP / Continue : vérifier FALLBACK. Réactiver le device en lecture : une grande
   différence doit se confirmer puis se verrouiller sans corrections répétitives.
   Refaire après Stop ; SPP doit être ignoré lorsque l'ABS est fraîche.
8. Arrêter / Relancer depuis Show Control ; vérifier disparition de l'ancien PID,
   un seul nouveau PID et reprise du diagnostic. Redémarrer Show Control pour
   vérifier son autostart existant.
9. Avec un monitoring sûr, basculer l'audio principal vers le distant à plusieurs
   positions, après locates et après lecture prolongée. Noter l'écart audible
   et la tolérance opérationnelle retenue. Il ne s'agit pas de synchro sample-accurate.

Validation matérielle nécessaire avant exploitation ; elle n'est pas couverte
par les tests déterministes ni par la compilation universal2.

## Résultat de validation de cette modification

- Build universal2 arm64 / x86_64 et vérification de signature : OK, dans `/tmp`.
- Tests natifs du bridge : OK.
- Tests de gestion Show Control : 3 tests OK.
- Test existant `test_remote_passive_feedback.py` : échec indépendant dans son
  environnement simulé, `NameError: record_go_midi_expectations`.
  Ni `app.py` ni ce test n'ont été modifiés par ce travail.
- Binaire du dépôt non remplacé ; aucun processus en exploitation redémarré.
- Tests physiques avec les deux Macs : non exécutés.
