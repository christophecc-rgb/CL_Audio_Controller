# Packaging Show Audio — validation du 11 septembre 2026

Bundles construits depuis le working tree validé :
- CL Audio Show Control.app : universal2, serveur 5050.
- CL Show Audio Builder.app : arm64, interface Tk et FFmpeg embarqués.

Construction depuis la racine (choisir une destination neuve) :

```sh
PYINSTALLER_CONFIG_DIR="$PWD/build/pyinstaller-cache" .venv/bin/python -m PyInstaller --workpath build/show-audio --distpath Releases/show-audio-test 'CL Show Audio Builder.spec'
.venv/bin/python -m PyInstaller --workpath build/controller --distpath Releases/show-audio-test 'CL Audio Controller.spec'
```

La configuration Show Audio est initialisée depuis show_audio.json puis conservée
sous ~/Library/Application Support/CL Show Audio Builder/show_audio.json.
Les configurations existantes ne sont pas écrasées. FFmpeg est embarqué avec ses
dépendances ; Swift et les outils de compilation Apple restent requis sur le Mac.
Ableton Live et AbletonOSC restent des prérequis externes.

Vérifications effectuées : build des deux apps, signatures ad hoc valides,
architectures, encodage MP3 320 kbit/s avec le FFmpeg embarqué, 821 tests généraux
(3 avertissements de threads), puis 309 tests Show Audio/packaging après ajout
des tests de chemins persistants et de FFmpeg embarqué.

Validation réelle restante : fermer les versions Terminal et anciennes apps,
lancer Show Control puis Show Audio Builder, autoriser le contrôle d'Ableton
si macOS le demande, exporter un medley, vérifier MP3, nom et restauration de boucle.
Les exports réels précédents validaient le code lancé depuis le Terminal.
Les bundles sont signés ad hoc, non notarisés. Le Builder est Apple Silicon uniquement.
