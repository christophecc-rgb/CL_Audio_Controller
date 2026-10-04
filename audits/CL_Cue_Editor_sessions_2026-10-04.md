# Audit CL Cue Editor — 4 octobre 2026

Audit des sources actuelles et lecture directe des fichiers utilisateur. Aucune session modifiée, aucune activation ni publication. Les tests utilisent un stockage temporaire. Le comportement du bundle installé et les dialogues natifs de téléchargement restent à vérifier en situation.

## Architecture et données

CL Cue Editor est une fenêtre pywebview locale ouverte sur http://127.0.0.1:5050/show-info/builder. Le moteur CL Show Control doit tourner sur le même Mac. Les données appartiennent au serveur, pas à la fenêtre. Les routes Builder refusent les connexions non locales.

Stockage : ~/Library/Application Support/CL Audio Show Control/ShowCue ; sessions.json contient le registre et la session active ; Sessions/<identifiant>/showcue_builder.json contient le Builder ; show_cues.json contient la conduite ; show_cues_audio contient les fichiers audio.

Inventaire lu : session active OP 2026, Builder 133 cues / 14 affectations / révision 343, conduite 144 cues. MPC : Builder 56 cues / 4 affectations / révision 30, conduite 54 cues. Session actuelle : conduite 19 cues, aucun fichier Builder présent. Les écarts ne permettent pas de conclure à une perte sans comparer chaque cue.

## Parcours vérifié

- Enregistrer écrit le Builder de la session active ; autosauvegarde après 750 ms sur les tables, file de sauvegarde et contrôle de révision. Les erreurs d’autorisation restent bloquantes.
- Ouvrir une session active celle-ci globalement sur le serveur puis recharge la page : ce choix concerne aussi ShowCue et les autres fenêtres.
- Importer un .showcue ou .showcue.zip crée une nouvelle session, renomme les doublons avec un suffixe, puis la page l’active. Ce parcours n’enregistre pas les modifications en cours de la session précédente.
- Une archive .showcue est un ZIP : manifeste, conduite, Builder lorsque présent, fichiers audio référencés disponibles. Elle ne contient pas tout l’environnement de la suite, les bibliothèques externes ni les réglages de sécurité.
- Un Builder vide ou absent est reconstruit depuis la conduite lors du chargement, puis persisté. Un Builder déjà rempli n’est pas reconstruit. La récupération dépend des métadonnées de conduite disponibles ; elle ne recrée pas tous les détails d’un Builder original perdu.
- XLSX/CSV : export du Builder enregistré, pas archive complète du show. L’export synchronise certains timecodes avec la conduite officielle. Import complet : prévisualisation, adoption en mémoire, enregistrement. Un import de distribution séparé conserve la conduite.
- Prévisualiser ShowCue sauvegarde d’abord le Builder. La confirmation de transfert ajoute ou remplace les cues correspondantes dans la conduite, avec contrôles de session et de contenu ; c’est distinct d’Enregistrer. Les suppressions ne sont pas appliquées comme une simple copie intégrale du Builder.

## Constats prioritaires

1. Export natif : showcue_builder_desktop.py n’active pas webview.settings ALLOW_DOWNLOADS. La bibliothèque installée le désactive par défaut ; son code Cocoa annule les réponses non affichables lorsque ce réglage est faux. Les exports XLSX et archives sont donc susceptibles d’être annulés dans la fenêtre native. Confirmer avec le bundle installé ; corriger et tester le dialogue Enregistrer sous.
2. Export et sauvegarde : les exports sont des liens directs GET sans attente de save() / builderSaveQueue. Un clic avant la fin de l’autosauvegarde ou après un refus exporte la version serveur précédente.
3. Ouverture/import : openSession et importArchive ne vident pas la file de sauvegarde avant activation/rechargement. beforeunload efface le brouillon local. Des changements non sauvegardés peuvent être perdus lors d’un changement de session ou d’une fermeture normale ; la sauvegarde différée peut aussi être refusée après activation.
4. Brouillon : la restauration supprime un brouillon dont la révision diffère du serveur. Un travail non sauvegardé ne bénéficie donc pas d’un parcours de récupération ou de comparaison fiable.
5. Deux documents : Enregistrer et Valider passent par la même sauvegarde Builder ; les libellés ne distinguent pas assez préparation, conduite opérationnelle et export portable.
6. save-transport existe côté serveur mais aucun appel trouvé dans la page : fonctionnalité non exposée par ce parcours. Cette route écrit dans le premier CL Transport et peut remplacer un fichier homonyme.

## Procédure provisoire

Démarrer le moteur CL, ouvrir Safari sur http://127.0.0.1:5050/show-info/builder. Déverrouiller localement l’administration et autoriser la configuration si nécessaire. Ouvrir la session souhaitée. Après modification, cliquer Enregistrer et attendre SAUVEGARDÉ sans erreur. Pour mettre la conduite à jour, utiliser Prévisualiser ShowCue, examiner le bilan, puis confirmer le transfert. Exporter ensuite le show actif en .showcue depuis SHOWS / SESSIONS. Vérifier que le fichier existe ; CSV/XLSX servent aux échanges de tableaux et ne remplacent pas cette sauvegarde. Enregistrer et attendre la confirmation avant toute ouverture/import/fermeture. Réimporter une archive uniquement pour une restauration volontaire : cela crée une copie de session.

## Validation

105 tests Python et 16 sous-tests passent (restauration, import V1, Builder, conduite) ; scénario JS de gestion des sessions réussi. Ils ne couvrent pas le dialogue natif de téléchargement ni tous les risques de brouillons, d’exports avant sauvegarde et de navigation pendant une écriture. Pas d’essai matériel ni de comparaison exhaustive des deux conduites utilisateur.

## Ordre de correction recommandé

Fiabiliser les téléchargements natifs ; garantir sauvegarde avant export/navigation avec blocage en cas d’échec ; conserver les brouillons et proposer récupération/comparaison ; rendre visibles le nom de session et les états de sauvegarde/publication ; ensuite réorganiser l’ergonomie autour de Ouvrir, Modifier, Enregistrer, Mettre à jour ShowCue et Sauvegarder le show.
