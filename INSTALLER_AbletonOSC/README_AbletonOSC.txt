INSTALLATION ABLETONOSC

Source officielle : github.com/ideoforms/AbletonOSC

Important : la documentation officielle actuelle indique qu'AbletonOSC nécessite Ableton Live 11 ou plus.
Pour Ableton Live 10, l'installation peut fonctionner selon la version du script, mais ce n'est pas garanti par le dépôt officiel actuel.

Installation automatique :
1. Double-cliquer sur Installer_AbletonOSC_Officiel.command.
2. Redémarrer Ableton Live.
3. Aller dans Préférences > Link/Tempo/MIDI.
4. Choisir AbletonOSC comme Surface de contrôle.

Chemin macOS utilisé :
~/Music/Ableton/User Library/Remote Scripts/AbletonOSC

Ports attendus par Ableton Web Remote :
- AbletonOSC reçoit sur 11000
- Ableton Web Remote reçoit les réponses sur 11001

Extension en lecture seule requise par CL Audio Controller :
- /live/song/get/file_path
- /live/song/get/name

La version amont inspectée ne publie pas encore ces deux propriétés Song.
Le fichier song-file-path-readonly.patch contient l'extension minimale proposée
au projet AbletonOSC. Le script d'installation officiel ci-dessus ne l'applique
pas automatiquement : vérifier la version amont avant toute réinstallation.
Le patch enregistre uniquement les deux routes de lecture ; il n'ajoute ni route
d'écriture, ni listener LOM pour ces propriétés non observables.

Découverte Bonjour optionnelle pour CL Show Control (macOS) :
- Fermer Live puis exécuter : python3 install_bonjour.py
- Pour une User Library personnalisée, ajouter --target '/chemin/AbletonOSC'.
- Relancer Live avec AbletonOSC actif ; le lecteur annonce _cl-ableton._udp.
- Dans Show Control : Distant → sélectionner → Appliquer → Tester la connexion.
- L'installeur conserve manager.py et les extensions existantes ; il sauvegarde
  __init__.py avant de modifier uniquement l'import de Manager.
- Une réinstallation officielle complète retire cette extension optionnelle.
- Procédure complète et validation deux Macs : docs/ABLETON_BONJOUR.md dans le repo.
