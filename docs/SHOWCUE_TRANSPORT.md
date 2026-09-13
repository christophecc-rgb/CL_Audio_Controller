# Cartographie avant modification — 12 septembre 2026

État initial : 11 fichiers suivis modifiés (Show Audio, MIDI et packaging),
`.codex/` et `vendor/` non suivis. Les différences packaging ont été lues avant édition.

## Runtime constaté

`CL Audio Controller.spec` construit `CL Audio Show Control.app` avec
`launcher_control.py`. Celui-ci charge dynamiquement `app.py` depuis son runtime.
`CL ShowCue.spec` et `CL ShowCue Builder.spec` construisent des fenêtres pywebview
qui attendent respectivement `/show-info` et `/show-info/builder` sur localhost:5050.
Elles ne contiennent pas de serveur.

Le 12 septembre, le PID 51778 sur 5050 est Python 3.14 exécutant `app.py`,
et non un exécutable de bundle. Ce constat ne valide pas le runtime distribué.

Le spec serveur embarque app.py, device_profiles.py, show_cues.py,
showcue_builder.py, console_title_library.py, remote_window.py, les dossiers
complets templates/static/assets, cl_audio_logo.png et les données historiques.
Il manque la déclaration explicite de showcue_pdf_import.py et pypdf.
Les pages ShowCue utilisent show_info.html, showcue_builder.html et
assets/paradis latin.jpg. Les autres routes du serveur requièrent index.html,
ab.html et arrangement.html : conserver tous les templates et assets.
Le Builder XLSX utilise zipfile et ElementTree, CSV utilise csv ; PDF utilise pypdf.

## Données existantes

Sessions : ~/Library/Application Support/CL Audio Show Control/ShowCue/
(registre sessions.json, Sessions/session_*/show_cues.json,
showcue_builder.json et show_cues_audio/). Aucun format .showcue.zip ni route
d'import/export de session trouvé dans les sources actuelles. L'archive ajoutée
réutilisera ces documents et leurs validateurs.

Bibliothèques effectivement lues :
~/Library/Application Support/CL Audio Controller/Console Files/CL5.titles.json
et QL1.titles.json. Comptage réel : CL5 123 entrées (1..128), QL1 107 (9..126).
Sources déclarées : cl5 memoires.CLF et QL1 mem.CLF.
Les nombres historiques 151/164 ne sont pas ceux des bibliothèques actives.
La résolution MIDI existante reste limitée à ses mémoires valides ; aucune
extension de plage n'est nécessaire pour distribuer les fichiers actifs.

## Architecture retenue

Un serveur partagé dans CL Audio Show Control.app ; deux fenêtres dédiées.
CL_Transport externe aux bundles, installé dans ~/Applications/CL Audio/CL_Transport
(convention utilisateur de l'installateur existant). Recherche : variable
CL_TRANSPORT_ROOT, dossier voisin des apps/kit ou installation utilisateur,
stockage legacy, puis bibliothèque embarquée. Les ressources et les sessions
utilisateur sont conservées lors de la désinstallation.
