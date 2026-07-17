# Environnement de build — CL Audio Controller

## Application de référence

- Nom : CL Audio Controller
- Version : 2.0.0
- Numéro de build : 4
- Identifiant macOS : `com.claudio.controller`
- Point d'entrée : `launcher_control.py`
- Configuration : `CL Audio Controller.spec`
- Bundle de référence : `dist/CL Audio Controller.app`

## Python

- CPython 3.14.5
- Distribution framework de python.org
- Emplacement observé : `/Library/Frameworks/Python.framework/Versions/3.14/`
- Compilateur du framework : Clang 21.0.0

Un environnement virtuel local `.venv` est recommandé. Le code sait l'utiliser en mode développement lorsqu'il existe.

## PyInstaller et architecture

- PyInstaller 6.21.0
- pyinstaller-hooks-contrib 2026.6
- Cible : `universal2`
- Architectures du bundle : `arm64` et `x86_64`
- Version minimale déclarée par l'exécutable : macOS 11.0
- SDK déclaré par l'exécutable : macOS SDK 26.2
- Signature : ad hoc
- UPX : désactivé
- Stripping : désactivé
- Console : désactivée

Le système exact du build original n'est pas enregistré. L'environnement inspecté utilisait macOS 26.5.2 sur Apple Silicon, sans que cela prouve la version active lors du build.

## Dépendances principales

Les versions complètes sont épinglées dans `requirements.txt`.

### Application

- Flask 3.1.3
- Werkzeug 3.1.8
- Jinja2 3.1.6
- python-osc 1.10.2
- pywebview 6.2.1

### Interface macOS

- pyobjc-core 12.2
- pyobjc-framework-Cocoa 12.2
- pyobjc-framework-WebKit 12.2

### Construction

- PyInstaller 6.21.0
- pyinstaller-hooks-contrib 2026.6
- packaging 26.2
- altgraph 0.17.5
- macholib 1.16.4
- setuptools 82.0.1

## Ressources nécessaires

Le `.spec` doit être lancé depuis la racine du projet avec les chemins suivants inchangés :

```text
launcher_control.py
app.py
remote_window.py
cl_audio_logo.png
CL_AUDIO.icns
arrangement_markers.json
templates/
static/
assets/
M4L/
```

Le `.spec` incorpore `app.py`, `remote_window.py`, le logo, les modèles HTML, les fichiers statiques, toutes les images, le dossier Max for Live et le JSON de repères.

## Dépendances externes

### Ableton Live et AbletonOSC

AbletonOSC doit être installé sous :

```text
~/Music/Ableton/User Library/Remote Scripts/AbletonOSC
```

Il doit être sélectionné comme surface de contrôle dans Ableton Live. Sa version ou son commit validé reste à enregistrer formellement.

L'installation active contrôlée le 17 juillet 2026 ne contient pas de métadonnées Git ni de version embarquée exploitable. Le dossier porte une date de modification locale du 9 juillet 2026, mais cette date ne permet pas d'identifier un commit. Le commit actuellement utilisé est donc **inconnu**. Toute future installation devra être effectuée à partir d'un commit ou d'une version explicitement figé et consigné ici.

### Max for Live

Le pont source se trouve sous :

```text
M4L/XFADER_OSC_BRIDGE_v8_OSC_REMOTE_STORE_ID.maxpat
```

Le device compilé `.amxd` reste un livrable externe. Il doit être chargé sur la piste Master et écouter sur UDP 9001.

### LTC Display

L'entrée LTC sur UDP 63123 est facultative pour les autres fonctions de l'application.

## Ports utilisés

| Port | Protocole | Rôle |
|---:|---|---|
| 5050 | TCP/HTTP | Serveur Web principal sur `0.0.0.0` |
| 5055 | TCP/HTTP | Panneau de contrôle sur `127.0.0.1` |
| 11000 | UDP | Commandes AbletonOSC |
| 11001 | UDP | Réponses AbletonOSC |
| 9001 | UDP | Pont Max for Live |
| 63123 | UDP | Entrée LTC Display |

## Procédure de reconstruction

1. Utiliser macOS sur une machine capable de produire un bundle `universal2`.
2. Installer CPython 3.14.5 depuis python.org.
3. Créer un environnement `.venv`.
4. Installer les versions de `requirements.txt`.
5. Vérifier que toutes les ressources attendues sont présentes.
6. Lancer PyInstaller depuis la racine avec `CL Audio Controller.spec`.
7. Ne pas écraser le bundle de référence lors du premier contrôle.
8. Comparer les ressources, métadonnées et architectures.
9. Exécuter les tests fonctionnels ci-dessous.

## Validation fonctionnelle

Vérifier :

1. le lancement du bundle ;
2. la fenêtre Cocoa pywebview ;
3. l'interface sur `127.0.0.1:5050` ;
4. l'accès depuis le réseau local ;
5. les commandes et retours AbletonOSC ;
6. les locators Arrangement ;
7. le repli `arrangement_markers.json` ;
8. le crossfader Max for Live ;
9. l'entrée LTC ;
10. les architectures arm64 et x86_64.

## Limitations connues

- Le macOS exact et la version exacte des outils Xcode du build original ne sont pas prouvés.
- Le commit de l'installation AbletonOSC actuelle est inconnu ; toute future installation doit utiliser une référence explicitement figée.
- Le lien de version entre le `.maxpat` et le `.amxd` reste à confirmer.
- Les horodatages, chemins de build, bytecodes et signatures peuvent modifier les SHA-256.
- Le bundle est signé ad hoc et non notarisé.
- Le serveur Web principal est exposé sur le réseau local.
- `app.py` peut terminer un processus occupant le port 5050 au démarrage.
- Un bundle de validation ne doit pas être lancé en parallèle de l'application active.
- Le script d'installation AbletonOSC peut remplacer l'installation existante et ne doit pas être exécuté sans contrôle préalable.
