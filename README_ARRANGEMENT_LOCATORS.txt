ONGLET ARRANGEMENT — LOCATORS ABLETON AUTOMATIQUES

Cette version ne nécessite plus de recopier les noms des repères à la main.

Principe :
- Ableton Live reste en Vue Arrangement.
- Tu crées/nommes tes Locators directement dans ton Set Ableton.
- L'onglet Arrangement lit automatiquement ces cue points via AbletonOSC :
  /live/song/get/cue_points
- La liste déroulante de l'iPhone est remplie avec les noms du Set.
- Le saut vers un repère utilise :
  /live/song/cue_point/jump

Commandes conservées :
- Play
- Pause / Continue
- Stop
- Début
- Repère précédent / suivant
- Liste déroulante + Go
- Boutons directs par repère

Repli de sécurité :
Si ta version d'AbletonOSC ne renvoie pas les cue points, l'application repasse automatiquement sur arrangement_markers.json.
Dans ce cas, l'iPhone affichera : "Mode repli : repères chargés depuis arrangement_markers.json".

Important :
AbletonOSC exprime current_song_time et les cue points en beats Live, pas en secondes réelles. C'est normal et cohérent avec l'API Ableton Live.

Checklist :
1. Ouvrir Ableton Live.
2. Vérifier qu'AbletonOSC est sélectionné comme Surface de contrôle.
3. Ouvrir le Set Ableton avec tes Locators.
4. Lancer Ableton Web Remote.
5. Ouvrir l'onglet Arrangement sur l'iPhone.
6. Vérifier que le texte indique : "Repères lus automatiquement depuis les Locators du Set Ableton".
