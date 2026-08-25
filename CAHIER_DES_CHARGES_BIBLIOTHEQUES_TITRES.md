# Bibliothèques de titres consoles

## Évolution consolidée

La source des titres consoles doit être choisie explicitement entre `Titres Ableton` et
`Bibliothèque de titres importée`. Ce choix est persistant, publié par le serveur et
consommé sans logique parallèle par la télécommande et CL MIDI Network Assistant.

La bibliothèque importée prend en charge Yamaha CLF ainsi que CSV, TSV, JSON et TXT
structuré. Chaque import est validé puis normalisé dans une représentation canonique
contenant la console, le numéro de mémoire affiché, le titre, la provenance et la date
d'importation. Les numéros Program Change, offsets et calculs expected/returned restent
inchangés.

Le stockage canonique est
`~/Library/Application Support/CL Audio Controller/Console Files/`, séparément pour CL5
et QL1. L'activation utilise un remplacement atomique avec sauvegarde de la version
précédente. Un import invalide, vide, trop volumineux, ambigu ou dangereux ne modifie
jamais la bibliothèque active.

Les anciens fichiers `~/Desktop/CL5.CLF`, `~/Desktop/ql1.CLF` et
`~/Desktop/QL1.CLF` restent détectables. Leur migration est sûre, ne supprime ni ne
modifie l'original et ne devient canonique qu'après validation et copie réussies.

L'interface locale propose pour chaque console le choix de fichier, le glisser-déposer,
les formats acceptés, un aperçu, les avertissements et l'état de la bibliothèque. La
télécommande distante reste consultative pour les fichiers mais affiche le mode actif,
l'état des bibliothèques et la provenance exacte du titre présenté.

En mode Ableton, les titres attendus et retournés utilisent explicitement le contexte
Ableton existant. En mode bibliothèque importée, aucun repli silencieux vers Ableton
n'est permis : une mémoire absente produit un message explicite propre à la console.

Les formats texte utilisent UTF-8 (avec BOM accepté) et les fins de ligne Unix ou
Windows. CSV/TSV acceptent `memory,title` pour une zone de console et
`console,memory,title` pour un fichier multiconsole. JSON accepte un objet avec
`console` et `scenes`, ou `consoles` contenant les listes CL5/QL1. TXT utilise une ligne
`mémoire<TAB>titre` ou `console<TAB>mémoire<TAB>titre`. Les doublons exacts sont
signalés et ignorés ; deux titres différents pour la même console et mémoire rendent
l'import ambigu et le font échouer.

La validation couvre notamment tous les formats, UTF-8, CRLF, doublons, plages mémoire,
taille et nombre d'entrées, sécurité des noms, atomicité, sauvegarde, migration,
persistance, absence de repli, publication de provenance et invariance MIDI.
