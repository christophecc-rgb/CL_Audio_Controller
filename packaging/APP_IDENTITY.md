# Identité des applications CL

Le catalogue de référence est `resources/app_identity.json`. Il fixe les noms
visibles, les libellés courts, les accents colorés et les anciens noms.

| Application | Icône |
|---|---|
| CL Show Control | CONTROL — rouge |
| CL Audio Export | AUDIO EXPORT — rose |
| CL ShowCue | SHOW CUES — cyan |
| CL Cue Editor | CUE EDITOR — mauve |
| CL Arrangement Builder | ARRANGEMENT — orange |
| CL MIDI & RTP Diagnostic | MIDI RTP DIAG — or |
| CL MIDI Network Manager | MIDI NETWORK — vert turquoise |
| CL MIDI Analyzer | MIDI ANALYZER — bleu clair |
| CL MIDI Performance Monitor | MIDI PERFORMANCE — bleu soutenu |
| CL MIDI RTP Agent | MIDI RTP — violet |
| Créer le Kit CL | KIT — gris argent, mallette |
| Installer la Suite CL | INSTALL — vert clair, flèche entrante |
| Désinstaller la Suite CL | UNINSTALL — bronze, retrait |
| CL Ableton Remote (distribution intermédiaire) | REMOTE — sable |

CL ShowCue affiche la conduite. CL Cue Editor prépare et modifie cette conduite.
CL Audio Export produit les fichiers WAV/MP3. CL Arrangement Builder construit
l’arrangement dans Ableton. CONTROL identifie uniquement le panneau principal.

`scripts/generate_app_icon_variants.py` génère les PNG et ICNS de la famille,
ainsi que les alias historiques et les différentes tailles de `icon.iconset`.
`scripts/verify_app_identity.py` vérifie avant export les noms et les ICNS de
chaque bundle. Une icône de contrôle réutilisée par erreur pour l’éditeur ou
l’export audio bloque donc la création du kit.

Les identifiants de bundle, noms d’exécutables, fichiers .spec, clés de composants,
Remote Scripts et chemins de stockage restent stables. Par exemple, les données
ShowCue restent dans `Library/Application Support/CL Audio Show Control/ShowCue`
et les réglages audio dans `Library/Application Support/CL Show Audio Builder`.
Ne pas renommer ces dossiers manuellement.

L’installateur de la suite retire les anciennes applications vers sa Corbeille
datée uniquement après avoir copié et vérifié leur remplaçante. Le désinstallateur
accepte les noms anciens et nouveaux attestés dans le manifeste. Les ressources
personnelles de CL_Transport sont conservées. Quitter les applications avant
une mise à jour ; les installations réelles ne sont pas modifiées par un build.
