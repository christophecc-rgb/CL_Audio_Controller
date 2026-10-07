# Builder : interface compacte et modification en masse — 7 octobre 2026

## Audit et choix

L’ancien écran réservait beaucoup de hauteur aux sessions, aux chemins de fichiers, aux explications et aux actions secondaires. Les actions des cues partageaient la cellule du matériel. Un ancien tri par TC dans `render()` réordonnait les cues après chargement : il empêchait de conserver un déplacement manuel et mélangeait les TC PRESHOW à 18h avec ceux du SHOW.

L’en-tête fixe regroupe l’identité du show, la sauvegarde du Builder, les menus Importer / Exporter / Organiser, le casting, les filtres et les actions ShowCue distinctes. Les explications détaillées sont repliées. Le casting reste accessible par son bouton. Les lignes présentent six colonnes, avec sélection permanente et actions compactes munies de noms accessibles. Les longues valeurs ont une infobulle ; les détails complets restent accessibles.

## Sessions et échanges

Le panneau de sessions original est déplacé, sans duplication, dans une seule fenêtre modale « Gérer les sessions ». Ses commandes et identifiants restent les mêmes : ouvrir, nouvelle session, renommer, dupliquer, supprimer, importer une copie `.showcue`, sauvegarder le show complet et consulter les archives détectées.

Importer conserve ses workflows existants CSV/XLSX, distribution, PDF et ShowCue. Le compte rendu d’import est compact et repliable. Adoption puis sauvegarde explicite du CSV/XLSX restent nécessaires. Aucun parseur ni route n’a été changé. Organiser contient les trois commandes originales : regroupement par phases, tri SHOW par TC, tri PRESHOW par TC. Le chargement conserve désormais l’ordre sauvegardé ; les tris nécessitent une action de l’utilisateur.

## Modification en masse

- Case à cocher : ajout/retrait ; clic sur une ligne : sélection unique ; Cmd/Ctrl : ajout/retrait ; Majuscule : plage visible.
- Barre contextuelle : nombre sélectionné, phase, section, type, destinations, déplacement, suppression et désélection.
- Les valeurs mixtes affichent « — valeurs multiples — ». Un changement exige une valeur et un clic sur Appliquer.
- Phase et section sont des champs distincts : modifier l’un ne remplace pas l’autre.
- Destinations : seuls les boutons FOH/RET/PLT/LUM explicitement changés sont appliqués ; les valeurs mixtes sont indéterminées.
- Déplacement avant/après un autre cue, au début ou à la fin, en conservant l’ordre relatif du groupe.
- Suppression : confirmation portant sur le nombre de cues. Les autres modifications ne demandent aucune confirmation.
- Les commandes de rôles existantes sont conservées dans le sous-menu Rôles.
- La sélection reste disponible après la sauvegarde. Elle utilise les cases source et le mécanisme existant de conservation, sans nouvelle source d’ordre.
- Les champs non concernés, notes, rôles, équipements et timecodes sont conservés.
- Les modifications suivent le mécanisme de sauvegarde existant du Builder ; aucun nouveau système de sauvegarde n’a été ajouté.

## Local et distant

Local : édition et opérations batch disponibles. Distant : même présentation, filtres, sessions consultables et détails disponibles ; sélection et mutations désactivées. La politique serveur et les permissions n’ont pas été modifiées.

## Vérification visuelle

Jeu synthétique isolé de 134 cues, serveur temporaire sans connexion au moteur spectacle. Mesures en pixels CSS, avec les mêmes données avant/après :

| Mesure | Ancien 1512×900 | Nouveau 1512×900 | Nouveau 1280×800 |
|---|---:|---:|---:|
| En-tête | 319 px | 119 px | 119 px |
| Ligne simple | 79 px | 32,5 px | environ 32,5 px |
| Cues complets visibles | 4 | 19 | 16 |
| Débordement horizontal | — | aucun | aucun |

Captures dans `docs/builder-ui/` : before-1512.png, after-1512.png, after-1280.png, batch-1512.png, sessions.png, remote-1512.png. Les captures sont prises dans le navigateur ; leur résolution bitmap peut différer des dimensions CSS selon l’échelle du navigateur.

Essai UI effectué : sélectionner huit cues, appliquer SHOW puis PRESHOW, vérifier les TC, déplacer un groupe en fin de document, enregistrer et recharger. Les huit identifiants et TC restent dans le même ordre relatif. La sélection reste active après une sauvegarde. Lecture seule vérifiée : sauvegarde et sélection désactivées, Détails et consultation des sessions disponibles. Aucune erreur JavaScript observée sur l’écran final.

## Fichiers de cette intervention

- templates/showcue_builder.html : chargement du layout et conservation de l’ordre au rendu.
- static/showcue-editor.js : colonne Actions, sections/phases compactes, sélection et rafraîchissement partagé.
- static/showcue-builder-layout.js : déplacement des contrôles originaux, modale de sessions et actions batch.
- static/showcue-builder-layout.css : densité, en-tête et barre contextuelle fixes, disposition adaptative.
- static/showcue-phase-order.js : accès au classement logique existant et lecture correcte des sélecteurs.
- static/showcue-builder-access.js : maintien de la consultation dans la nouvelle modale et reconnaissance des boutons Détails compacts.
- tests/js/test_showcue_builder_layout.cjs ; tests/test_builder_batch_persistence.py.

Les autres modifications déjà présentes dans le dépôt ont été conservées. Sauvegardes ciblées avant édition : `/private/tmp/cl-builder-ui-before-20261007/`.

## Tests et build

127 tests Python et 39 sous-tests réussis : Builder, ShowCue, persistence batch, ordre manuel, diagnostic preview et consultation distante. Sept suites JS ciblées réussies : layout/batch, accès distant, feedback import, menu import, phases/ordre, sessions et lifecycle. Syntaxe des fichiers JS et des 18 scripts intégrés vérifiée ; `git diff --check` réussi.

Build : `Releases/CL_Show_Control_Builder_UI_Redesign_2026-10-07/CL Show Control.app`. Signature locale ad hoc vérifiée avec `codesign --verify --deep --strict`. Cette vérification n’est pas une notarisation Apple.

Aucun commit, aucune installation. MIDI, GO, Ableton, RTP et logique spectacle non modifiés par cette intervention. Les essais visuels utilisent des données fictives ; aucun show utilisateur n’a été modifié.
