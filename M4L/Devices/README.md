# Sources Max for Live

Chaque périphérique est conservé avec :

- sa source éditable `.maxpat` ;
- ses scripts JavaScript externes lorsqu'ils sont utilisés ;
- ses ressources locales ;
- son périphérique `.amxd` prêt à installer.

## Périphériques

### Paradis Latin AutoScene

Deux variantes sont présentes :

- `Paradis Latin AutoScene.maxpat` et `.amxd` pour les versions actuelles ;
- `Paradis Latin AutoScene - Live 10.maxpat` et `.amxd` pour Live 10.

Les deux variantes utilisent `ParadisLatin_AutoScene.js` et
`paradis_latin_logo.jpg`. Le chemin du script dans les sources et les AMXD est
relatif : aucun chemin personnel n'est nécessaire.

### XFADER OSC BRIDGE v8

La source et l'AMXD sont réunis sous le même nom. Ce périphérique ne déclare
aucune dépendance JavaScript externe.

### LTC Display v2.0 Remote Config

La source, l'AMXD et `cache.js` sont conservés ensemble. Le patch référence
également `framerate.js`, mais ce fichier n'a pas été retrouvé dans le projet
Max, la bibliothèque Ableton, les sauvegardes ou les dépôts inspectés. Cette
dépendance doit être identifiée avant d'affirmer qu'une reconstruction depuis
la seule source est totalement autonome. L'AMXD validé reste inchangé.

### CL MIDI Console Monitor

Depuis la double écoute native de `CL MIDI Network Assistant`, ce device est
optionnel et conservé comme outil legacy/diagnostic. L’attendu canonique est le
Program Change réellement observé sur `Gestionnaire IAC Bus 1`; l’OSC du device
sur UDP 11001 reste un fallback et ne peut pas écraser une intention IAC.

Le moniteur se place en dernier effet MIDI sur la piste de commande CL5 ou
QL1. `midiin` reste relié directement à `midiout` : les octets MIDI traversent
le périphérique sans transformation. La sortie Program Change de `midiparse`
est copiée en OSC vers `/cl/midi-monitor/outgoing/cl5` ou
`/cl/midi-monitor/outgoing/ql1` selon le rôle choisi. La destination persistante
reste `127.0.0.1:11001` en mode local. Sur le Mac Ableton distant, renseigner
dans le périphérique l'hôte du Mac serveur et le `osc_reply_port` du profil
(11001 par défaut). La destination est réappliquée au chargement et dès qu'un
champ est modifié; UDP ne nécessite pas de connexion MIDI ou IAC.

Cette branche OSC est une observation passive : elle ne rejoint jamais
`midiout`, n'envoie aucun second message aux consoles et ne peut donc créer ni
doublon ni boucle CoreMIDI/IAC/RTP. Le rôle `CL5 retour` ou `QL1 retour` reste
réservé au flux physique reçu et n'alimente pas l'attendu Ableton.

## Installation

Les éléments destinés à l'installation directe sont regroupés dans
`M4L/Install/`. Les fichiers auxiliaires doivent rester dans le même dossier
que les périphériques qui les utilisent.
