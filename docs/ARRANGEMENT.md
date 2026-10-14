# Exploitation de l'Arrangement

L'onglet Arrangement lit les Locators/Cue Points du Set via AbletonOSC.
Le repère préparé et le dernier repère lancé sont distincts : choisir ou préparer
un repère ne doit pas être confondu avec son lancement par GO.
Le GO lance le repère préparé et prépare le suivant. Pause et STOP restent
les commandes de transport ; le chemin Pause → GO est couvert par
tests/test_arrangement_go_transaction.py.

Les positions de current_song_time et des cue points sont exprimées en beats
Live, pas en secondes. En cas d'indisponibilité des locators, le moteur conserve
le repli arrangement_markers.json. Ne pas modifier ce fichier de production
pour convertir ses unités pendant un nettoyage du dépôt.

Sources de référence : load_arrangement_markers et
execute_arrangement_marker_go dans app.py, templates/arrangement.html.
Les anciennes notes racine décrivaient des étapes successives de développement
et sont remplacées par cette page. Les appareils réels, les changements de
signature et les transitions de spectacle restent à valider sur une copie du Set.
