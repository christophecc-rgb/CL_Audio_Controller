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

## Installation

Les éléments destinés à l'installation directe sont regroupés dans
`M4L/Install/`. Les fichiers auxiliaires doivent rester dans le même dossier
que les périphériques qui les utilisent.
