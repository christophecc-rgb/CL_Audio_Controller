# Cycle de vie des simulateurs locaux CL5 / QL1

## Cause et périmètre

Le Dashboard ne restaurait les simulateurs qu'au démarrage de son interface, avec dix tentatives limitées dans le temps. Le background monitor était explicitement exclu. Les NSTask étaient connus uniquement de leur fenêtre ; le verrou de surveillance passive ne protégeait pas les lancements des simulateurs. Aucun suivi de server_instance_id ne remplaçait la paire après redémarrage du backend. SIGTERM ne passait pas par le nettoyage AppKit.

Cette correction concerne la supervision locale IAC. Les changements de nomenclature préexistants sont conservés. Pas de changement de Program Change, MTC, Hot Backup, IP, ports, CSV, CLF ou configuration RTP. Aucun commit ni reset.

## Fonctionnement

- Le propriétaire du verrou existant de surveillance passive supervise les retours locaux, interface ouverte ou background monitor. Une fenêtre secondaire exprime ses demandes via les préférences Auto existantes ; elle ne lance pas une deuxième paire.
- La supervision conserve le choix Auto et enabled existant. Pour la paire complète, activer Auto pour CL5 et QL1 une première fois. « Tout arrêter » efface cette demande. Quitter le propriétaire nettoie les enfants sans effacer Auto.
- Une seule requête /status en vol, délai réseau maximal de 3 secondes, aucune dépendance ajoutée au backend. Le timer existant interroge toutes les 2 secondes. La disponibilité dépend de l'identité du backend et des références CoreMIDI réelles, pas d'un délai de démarrage arbitraire.
- Une nouvelle identité, une absence de backend, ou une disparition/recréation des endpoints invalide les anciens retours et arrête l'ancienne paire. Le superviseur attend sa disparition dans l'inventaire des processus avant de lancer les remplaçants.
- Arguments locaux conservés : CL5 canal 1, QL1 canal 2, transport iac, endpoint `CL MIDI Return Test`, input-endpoint `Gestionnaire IAC Bus 1`, délai 80 ms. Seul `--owner-pid` est ajouté pour le nettoyage en cas de disparition du parent.
- Les enfants possèdent un verrou système exclusif par utilisateur et par label local. Les verrous ne sont pas supprimés du disque, pour éviter une course entre deux inodes. Le descripteur du propriétaire du monitor est close-on-exec.
- Les processus déjà suivis et ayant émis READY avec echo=on sont réutilisés. Les anciens processus sans preuve de readiness sont remplacés ; leur recherche utilise les arguments exacts, le nom d'exécutable, le propriétaire Unix et uniquement la route locale demandée. Aucun pkill global ajouté.
- Le décès isolé d'un enfant ne remplace pas son voisin. Les reprises sont espacées de 2, 4, 8, 16 puis 30 secondes. Le compteur se réinitialise après 30 secondes de santé. Sans endpoint, aucun lancement ; le retour de l'endpoint permet une nouvelle tentative. Un enfant sans READY est arrêté après 10 secondes. Les transitions sont consignées sous `local-simulator-supervision`.
- Les nouveaux simulateurs quittent aussi lorsque leur parent disparaît ou que leurs références d'endpoints changent. Ils ne modifient pas la logique d'écho MIDI.
- SIGTERM/SIGINT demandent l'arrêt AppKit. Les enfants suivis reçoivent TERM ; le manager continue sa boucle et conserve son verrou jusqu'à leur sortie. Après 3 secondes, les seuls NSTask enfants encore vivants reçoivent KILL. Le Guardian n'est lancé que par le propriétaire et seul son propre NSTask est arrêté. Sa disparition du parent provoque également sa sortie. Ses tentatives de lancement sont espacées d'au moins 30 secondes.
- Un ancien processus extérieur qui ignore TERM bloque le remplacement, avec état stopping ; le superviseur privilégie l'absence de doublons à un lancement forcé. Show Control reste indépendant.

## LaunchAgent

Le fichier installé `~/Library/LaunchAgents/com.claudio.midi-network-monitor.plist` a été lu : RunAtLoad=true, KeepAlive=true, ThrottleInterval=5. Cela exprime une surveillance persistante après fermeture de la fenêtre ou redémarrage de session. La persistance n'a pas été supprimée. Le générateur conserve RunAtLoad et KeepAlive et porte ThrottleInterval à 30 pour limiter les relances lorsqu'un autre propriétaire existe.

Le plist installé et les applications installées n'ont pas été remplacés dans ce chantier. Après distribution du nouveau build, KeepAlive peut relancer le monitor après son arrêt : l'ancien propriétaire nettoie d'abord ses enfants, puis le nouveau reprend la demande Auto. Fermer une fenêtre secondaire ne stoppe pas les enfants d'un autre propriétaire.

## Vérifications réalisées

- Compilation universelle arm64/x86_64, cible macOS 10.15, du Dashboard, du simulateur et du Guardian, dans `/tmp` : réussite.
- `python3 -m pytest -q tests/test_local_simulator_lifecycle.py tests/test_midi_endpoint_names.py tests/test_midi_network_assistant.py` : 16 réussites.
- Le test natif exécute réellement la machine de supervision avec inventaire/horloge/processus simulés : paire initiale, réconciliation répétée sans duplication, attente de sortie après changement d'identité, mort isolée, backoff, endpoint absent puis revenu, backend absent puis revenu, nettoyage à l'arrêt, anciennes instances multiples, READY absent et filtrage des arguments. Un fork vérifie également l'exclusion réelle du verrou entre processus.
- Suite élargie `test_midi_network_tools.py`, `test_midi_network_assistant.py`, `test_midi_endpoint_names.py` : 73 réussites, 18 échecs. Les assertions en échec portent sur des chaînes/structures hors des blocs changés ici (anciens libellés UI, disposition, transport, source de publication, nombre de cibles de build). Elles ne sont pas réécrites pour masquer ces écarts.
- `git diff --check` : réussite.
- Audit réel en lecture seule : deux anciens processus (93617 CL5 et 93623 QL1) et endpoints Gestionnaire IAC CL MIDI Return Test, MTC vers Logic, Ableton Clock et Bus 1 présents en source et destination. Au premier relevé /status indiquait local_dedicated mais « Aucun port MIDI détecté ». Au dernier relevé le serveur 5050 refusait la connexion. Aucun redémarrage de production ni message MIDI n'a été envoyé.

Les tests de machine d'état ne prouvent pas les retours MIDI physiques ni le comportement complet de l'application installée. Aucun GO opérateur effectué. Le nouveau build doit être distribué avant la validation suivante.

## Validation manuelle après installation du build

1. Lancer Show Control et Network Manager, mode local, Auto CL5 et QL1 activés.
2. Exécuter :

   ```sh
   pgrep -fl "CLYamahaConsoleSimulator"
   curl -sS http://127.0.0.1:5050/status
   ```

   Attendu : exactement deux lignes de processus, une CL5 et une QL1 ; console_return_mode = local_dedicated et console_return_source différent de « Aucun port MIDI détecté ».
3. Noter les PID. Ouvrir une deuxième fenêtre/instance du manager : toujours deux simulateurs, mêmes PID sains.
4. Redémarrer Show Control : les anciens PID disparaissent, une nouvelle paire apparaît après disponibilité effective du backend et des endpoints. Répéter les deux commandes.
5. Arrêter uniquement le PID CL5 identifié : seul CL5 est remplacé après backoff ; QL1 conserve son PID.
6. En séance de test hors exploitation, rendre un endpoint IAC requis indisponible, puis le rétablir sans le renommer : état waiting explicite, aucun empilement, reprise propre au retour.
7. Quitter le propriétaire Network Manager/monitor : vérifier la disparition de ses enfants et de son Guardian. Tenir compte de la relance volontaire par KeepAlive ; si une fenêtre secondaire reste ouverte, elle peut reprendre la supervision.
8. Un GO opérateur doit confirmer la mise à jour des cartouches retour sans redémarrage manuel des simulateurs. Cette étape reste à effectuer.
