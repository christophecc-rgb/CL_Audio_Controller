ONGLET ARRANGEMENT - ABLETON WEB REMOTE

Ajout :
- Nouvelle page iPhone : http://IP_DU_MAC:5050/arrangement
- Navigation en haut : Scènes / A-B / Arrangement
- Commandes : Play, Pause, Stop, Début, Repère précédent, Repère suivant
- Boutons de repères personnalisables pour une conduite de spectacle en Vue Arrangement

Configuration des repères :
- Modifier le fichier arrangement_markers.json à la racine du dossier REMOTES.
- Chaque entrée contient :
  - name : nom affiché sur l'iPhone
  - time : position en secondes dans la timeline Arrangement Ableton

Exemple :
[
  { "name": "01 - Ouverture", "time": 60 },
  { "name": "02 - Tableau 1", "time": 180 }
]

Important :
- Ableton doit rester en Vue Arrangement pour cet usage.
- Le transport utilise AbletonOSC.
- Le déplacement dans la timeline utilise l'adresse OSC standard : /live/song/set/current_song_time.
- Si ta version d'AbletonOSC ne répond pas à cette adresse, il faudra passer par un petit bridge Max for Live complémentaire.


MISE À JOUR LISTE DÉROULANTE
- Onglet Arrangement : une liste déroulante permet de choisir le repère voulu.
- Appuyer sur Go pour sauter au repère sélectionné.
- Les boutons de repères directs restent disponibles en dessous.
- Les repères se modifient toujours dans arrangement_markers.json.
