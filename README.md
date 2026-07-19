# CL Audio Controller

CL Audio Controller est une application macOS de pilotage d'Ableton Live. Elle réunit une interface native, une télécommande Web accessible sur le réseau local, des échanges OSC avec AbletonOSC, un suivi de l'arrangement et un pont Max for Live pour le crossfader.

La version de référence est **2.0.0** (build 4), identifiée par le bundle macOS `com.claudio.controller`.

## État du projet

CL Audio Controller constitue désormais un projet autonome : son code, ses ressources, sa configuration PyInstaller et sa documentation de reconstruction sont réunis dans ce dépôt. Le build de validation a confirmé qu'une application fonctionnellement équivalente au bundle de référence peut être reconstruite sans dépendre du workspace historique `AB_Launcher_LTC_DEV`.

La reproductibilité fonctionnelle est documentée et validée. Une identité binaire stricte n'est toutefois pas garantie, notamment à cause des métadonnées de build, des signatures, des horodatages et de la version exacte des outils Apple.

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

Les dossiers locaux `build/` et `dist/` contiennent des artefacts de référence. Ils sont exclus du suivi Git et restent uniquement disponibles comme éléments de comparaison locale.

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

Après installation, redémarrer Ableton Live et sélectionner AbletonOSC comme surface de contrôle.

L'installation active inspectée le 17 juillet 2026 est une copie de la branche `master` installée localement le 9 juillet 2026. Elle ne contient ni dossier `.git`, ni numéro de version, ni identifiant de commit vérifiable. **Son commit exact est donc inconnu et ne doit pas être déduit de sa date.** Avant toute nouvelle installation, choisir et documenter explicitement un commit ou une version d'AbletonOSC. Le script fourni dans `INSTALLER_AbletonOSC/` télécharge actuellement la branche mobile `master` et peut remplacer l'installation existante ; il ne doit pas être exécuté sans contrôle préalable.

CL Audio Controller utilise également deux lectures `Song` non encore publiées par la version AbletonOSC inspectée : `/live/song/get/file_path` et `/live/song/get/name`. L'extension déclarative correspondante est conservée dans `INSTALLER_AbletonOSC/song-file-path-readonly.patch` en attendant son éventuelle intégration en amont.

### Cohérence lors d'un changement de Live Set

Le serveur identifie principalement le Live Set par le chemin absolu fourni par `Song.file_path`. `/live/startup` déclenche une réinitialisation immédiate et la comparaison régulière du chemin pendant le rafraîchissement normal sert de garde complémentaire si cet événement est perdu. Un Set non enregistré reçoit une identité temporaire de la forme `unsaved:<génération>`.

Chaque réinitialisation incrémente `set_generation` et efface atomiquement les scènes, caches et états de lecture du Set précédent. Toutes les réponses HTTP contenant l'état publient `current_set_id` et `set_generation`. Les traitements asynchrones abandonnent leurs résultats si leur génération n'est plus courante ; les interfaces Session, A/B et Arrangement ignorent également toute réponse plus ancienne que la dernière génération acceptée.

Le diagnostic détaillé est silencieux par défaut. Pour afficher temporairement les événements préfixés par `[SET_GENERATION]` côté serveur et dans les consoles Web, lancer l'application avec `CL_AUDIO_GENERATION_DEBUG=1`.

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
| 63123 | UDP | Entrée optionnelle LTC Display, filtrée selon le profil Ableton actif |

Le serveur principal écoute sur `0.0.0.0`. Utiliser l'application uniquement sur un réseau de confiance et vérifier le pare-feu macOS.

### LTC Local et Distant

Le LTC utilise un flux UDP distinct d'AbletonOSC. La source et le périphérique de
référence sont `M4L/LTC Display v2.0 Remote Config.maxpat` et son `.amxd` associé ;
son calcul et son message historique `tc,sHH:MM:SS:FF` sont inchangés.

- En mode **Local**, conserver la destination `127.0.0.1` et le port `63123`.
- En mode **Distant**, saisir dans le périphérique Max for Live l'adresse LAN du
  Mac qui exécute CL Audio Controller, toujours sur le port `63123`.

Les deux adresses réseau ont des rôles opposés : le profil Ableton distant contient
l'adresse du Mac Ableton auquel le contrôleur envoie ses commandes sur UDP 11000,
alors que le périphérique LTC contient l'adresse du Mac contrôleur auquel le Mac
Ableton envoie le timecode sur UDP 63123. Le contrôleur écoute 63123 sur ses
interfaces réseau, mais n'accepte que la boucle locale en mode Local ou l'adresse
du Mac Ableton actif en mode Distant.

Si le pare-feu macOS du Mac contrôleur est actif, autoriser CL Audio Controller à
recevoir des datagrammes UDP sur 63123. Aucune découverte réseau n'est effectuée.

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

Le code et la documentation propres à CL Audio Controller sont distribués sous licence MIT ; voir `LICENSE`. Les composants tiers conservent leurs licences respectives, recensées dans `THIRD_PARTY_LICENSES.md`. Les droits sur les ressources graphiques et Max for Live doivent être confirmés avant toute publication publique.
