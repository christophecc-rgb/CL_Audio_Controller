# CL Cue Editor — fiabilisation des shows

Date : 4 octobre 2026. Rapport initial lu : CL_Cue_Editor_sessions_2026-10-04.md.

## Corrections

- Les exports attendent la file unique de sauvegarde. Le serveur vérifie aussi la session et la révision demandées : un refus d’administration ou un conflit bloque l’export.
- CSV, XLSX et .showcue passent par « Enregistrer sous… » dans la fenêtre native, avec écriture atomique, annulation distincte et chemin réel affiché. Safari reçoit un téléchargement nommé ; son emplacement dépend de ses préférences.
- Les réponses d’export portent Content-Disposition attachment, un type adapté, no-store et nosniff.
- L’ouverture d’un show et l’import attendent les sauvegardes. En cas d’échec, l’opérateur choisit de rester ou d’abandonner les modifications affichées. Une prévisualisation non adoptée n’est pas sauvegardée implicitement.
- Les modifications saisies pendant une sauvegarde restent présentes et sont enregistrées à la révision suivante. Les états de sauvegarde et de prévisualisation sont explicites.
- Fermeture/rechargement protégés ; brouillons conservés, comparaison et récupération explicites en cas de révision différente. La récupération prépare une prévisualisation ; elle n’écrase pas la version serveur. Le garde de fermeture natif évite de bloquer le thread graphique Cocoa.
- Nom du show actif et portée globale du changement de session affichés. L’import crée une nouvelle session et indique son nom ajusté en cas de doublon.
- Reconstruction seulement si le Builder est absent ou vide ; un Builder rempli reste intact. Les limites des métadonnées manquantes sont affichées.
- Sauvegarder le Builder, mettre à jour la conduite, exporter le tableau et sauvegarder le show complet sont distingués. L’archive contient Builder, conduite et audio référencé ; un audio absent bloque la création d’une archive incomplète.

## Vérifications automatisées

132 tests Python et 21 sous-tests passent : restauration, Builder, conduite, archives, import PDF, protections d’accès/administration et exports natifs.

Cinq scénarios JavaScript passent : sessions ; file de sauvegarde réelle ; brouillons ; cycle de vie/export ; courses export/sauvegarde. Ils couvrent notamment modification immédiatement avant export, sauvegarde en cours, nouvelles modifications pendant l’écriture, refus d’administration, conflit de révision, annulation de navigation, import non adopté, fermeture et récupération.

Deux tests Chrome passent, avec toutes les requêtes interceptées : consultation sans écriture, sauvegarde aller-retour, annulations, détails, rôles, filtres et affichage responsive.

CSV/XLSX : accents, valeurs, colonnes, affectations et réimport vérifiés sur données fictives. Archives .showcue/.showcue.zip : Builder, conduite, WAV, doublons et réimport vérifiés dans des répertoires temporaires.

## Vérifications réelles des fenêtres

Une fixture locale isolée utilise les fonctions de production d’export, de sauvegarde et de protection des brouillons, sans démarrer app.py ni contacter le moteur CL.

- Fenêtre native macOS : dialogues « Enregistrer sous… » pour les trois formats, fichiers effectivement écrits, chemin visible, annulation sans remplacement de page. Destination de test : /private/tmp/cl-cue-validation-20261004/Bureau. Contenu des fichiers et réimport contrôlés.
- Refus de sauvegarde natif : export bloqué avant le dialogue. Fermeture annulée et rechargement annulé gardent les modifications. Rechargement explicitement accepté, conflit de révision, comparaison puis récupération du brouillon testés ; la révision serveur 1 et son texte sont restés intacts après récupération en prévisualisation.
- Safari : trois téléchargements nommés effectivement reçus dans Téléchargements, page conservée. Fichiers fictifs CL_Cue_Test_20261004_81636a45.csv/.xlsx/.showcue contrôlés et réimportés ; WAV identique.
- Fenêtres et serveurs temporaires fermés après les essais.

## Limites précises

- Les applications installées n’ont pas été reconstruites ou remplacées. Le parcours natif a été testé depuis les sources sur une fixture, pas dans un nouveau bundle distribué.
- La persistance du profil natif est configurée et testée automatiquement ; la récupération après rechargement a été testée en fenêtre réelle. Un arrêt complet puis redémarrage de l’application installée avec un brouillon n’a pas été testé.
- Les ouvertures/imports avec annulation et erreurs sont couverts automatiquement ; pas de manipulation des sessions de production dans Safari ou l’application installée.
- Safari ne fournit pas au code de la page le chemin final ni une confirmation fiable d’enregistrement. L’interface annonce seulement le téléchargement demandé. Aucun changement des préférences Safari n’a été effectué.
- Reconstruction : les champs absents de la conduite et de ses métadonnées originales ne peuvent pas être inventés.
- OP 2026, MPC et les connexions réelles n’ont pas été modifiés. Aucun build, commit ou publication GitHub.

## Procédure opérateur

1. Ouvrir le show et vérifier son nom. Le changement concerne tout le serveur ShowCue.
2. Modifier puis « Enregistrer le Builder ». Attendre la confirmation ; cette action ne met pas à jour la conduite.
3. Si nécessaire, prévisualiser puis « Mettre à jour la conduite ShowCue ».
4. Choisir CSV/XLSX pour le tableau, ou « Sauvegarder le show complet .showcue » pour Builder, conduite et audio.
5. Dans la fenêtre native, choisir l’emplacement dans « Enregistrer sous… », y compris le Bureau. Dans Safari, consulter les téléchargements et les préférences du navigateur.
