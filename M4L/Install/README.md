# Max for Live à installer

Ce dossier accompagne CL Audio Controller afin de rendre son installation
transportable sur un autre Mac.

## Périphériques

- `XFADER OSC BRIDGE v8.amxd` : pont du crossfader A/B. À placer sur la piste
  Master et à utiliser avec le port UDP 9001.
- `Paradis Latin AutoScene.amxd` : périphérique AutoScene pour les versions
  actuelles d'Ableton Live.
- `Paradis Latin AutoScene - Live 10.amxd` : variante destinée aux Live Sets qui
  nécessitent la compatibilité Ableton Live 10.
- `LTC Display v2.0 Remote Config.amxd` : affichage et émission du LTC. Le port
  attendu par défaut est 63123 ; en mode distant, renseigner l'adresse du Mac
  exécutant CL Audio Controller.
- `ParadisLatin_AutoScene.js` et `paradis_latin_logo.jpg` : dépendances des
  deux variantes AutoScene. Elles doivent rester dans le même dossier que les
  `.amxd`.
- `cache.js` : dépendance JavaScript conservée avec le périphérique LTC.

## Installation

1. Ouvrir la bibliothèque utilisateur dans Ableton Live.
2. Copier les périphériques dans un dossier Max for Live de la bibliothèque.
3. Charger uniquement la variante AutoScene correspondant au Live Set.
4. Placer le X-Fader sur la piste Master lorsque la télécommande A/B est utilisée.
5. Enregistrer une copie de test du Live Set après configuration.

Ne jamais remplacer automatiquement un périphérique déjà utilisé dans un Live
Set de production. Tester d'abord une nouvelle instance dans une copie du Set.

Les sources éditables correspondantes sont conservées dans `M4L/Devices/`.
