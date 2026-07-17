# CL Audio Controller

CL Audio Controller est une application macOS de pilotage d'Ableton Live. Elle réunit une interface native, une télécommande Web accessible sur le réseau local, des échanges OSC avec AbletonOSC, un suivi de l'arrangement et un pont Max for Live pour le crossfader.

La version de référence est **2.0.0** (build 4), identifiée par le bundle macOS `com.claudio.controller`.

## Architecture

- `launcher_control.py` : point d'entrée de l'application et panneau de contrôle natif.
- `app.py` : serveur Flask, logique métier, communication OSC, arrangement et LTC.
- `remote_window.py` : fenêtre native pywebview de la télécommande.
- `templates/` : interfaces HTML.
- `static/` : feuilles de style et JavaScript.
- `assets/` : images utilisées par l'interface.
- `M4L/` : pont Max for Live source pour le crossfader.
- `arrangement_markers.json` : repères de secours lorsque les locators ne sont pas fournis par AbletonOSC.
- `CL Audio Controller.spec` : configuration PyInstaller de l'application macOS.
- `Diagnostics/`, `Guides/` et `INSTALLER_AbletonOSC/` : outils et documentation d'exploitation.

Les dossiers `build/` et `dist/` contiennent des artefacts de référence. Ils ne font pas partie du futur historique Git et ne doivent pas être supprimés avant validation d'un nouveau build.

## Prérequis

- macOS 11 ou ultérieur pour l'exécutable de référence ;
- Python 3.14.5, distribution framework de python.org recommandée ;
- dépendances épinglées dans `requirements.txt` ;
- Ableton Live avec Max for Live pour toutes les fonctions musicales ;
- AbletonOSC installé et sélectionné comme surface de contrôle ;
- le device Max for Live du crossfader chargé sur la piste Master.

## Installation de l'environnement de développement

Créer de préférence un environnement virtuel à la racine du projet :

```bash
/Library/Frameworks/Python.framework/Versions/3.14/bin/python3.14 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt
```

Ces commandes sont fournies à titre documentaire. Vérifier l'environnement et la sauvegarde avant toute installation.

## Dépendances externes

### AbletonOSC

AbletonOSC doit être installé sous :

```text
~/Music/Ableton/User Library/Remote Scripts/AbletonOSC
```

Après installation, redémarrer Ableton Live et sélectionner AbletonOSC comme surface de contrôle. La version ou le commit validé doit être figé avant toute réinstallation. Le script fourni dans `INSTALLER_AbletonOSC/` télécharge une source distante et peut remplacer l'installation existante ; il ne doit pas être exécuté sans contrôle préalable.

### Max for Live

Le pont source est fourni dans :

```text
M4L/XFADER_OSC_BRIDGE_v8_OSC_REMOTE_STORE_ID.maxpat
```

Le device doit écouter en UDP sur le port 9001 et être placé sur la piste Master. Le fichier `.amxd` compilé est traité comme un livrable externe et n'est pas versionné dans ce projet.

## Ports réseau

| Port | Protocole | Usage |
|---:|---|---|
| 5050 | TCP/HTTP | Serveur Web principal, accessible sur le réseau local |
| 5055 | TCP/HTTP | Panneau de contrôle local |
| 11000 | UDP | Commandes envoyées à AbletonOSC |
| 11001 | UDP | Réponses reçues depuis AbletonOSC |
| 9001 | UDP | Commandes envoyées au pont Max for Live |
| 63123 | UDP | Entrée optionnelle LTC Display |

Le serveur principal écoute sur `0.0.0.0`. Utiliser l'application uniquement sur un réseau de confiance et vérifier le pare-feu macOS.

## Construction macOS

La configuration de référence est `CL Audio Controller.spec`. Elle doit être utilisée depuis la racine du projet, sans modifier les chemins relatifs :

```bash
.venv/bin/python -m PyInstaller "CL Audio Controller.spec"
```

Pour le premier build de validation, ne pas écraser les dossiers `build/` et `dist/` de référence. Utiliser une copie de validation ou des chemins de sortie distincts. Comparer ensuite le nouveau bundle à `dist/CL Audio Controller.app` et réaliser les tests fonctionnels décrits dans `BUILD_ENVIRONMENT.md`.

## Limitations connues

- Une reconstruction fonctionnelle ne garantit pas un SHA-256 identique au bundle historique.
- La version exacte de macOS et des outils Xcode du build original n'est pas prouvée.
- Le bundle de référence est signé ad hoc et n'est pas notarisé.
- AbletonOSC et le device `.amxd` sont des dépendances externes.
- Au démarrage, `app.py` tente de libérer le port 5050 et peut arrêter un serveur existant sur ce port.
- Ne pas lancer simultanément le bundle de validation et l'application de référence.
- La compatibilité exacte avec chaque version d'Ableton Live doit être validée en conditions réelles.

## Licence

Aucune licence de publication n'a encore été choisie. Le projet ne doit pas être publié avant mise à jour du fichier `LICENSE` et vérification des droits sur les ressources graphiques.
