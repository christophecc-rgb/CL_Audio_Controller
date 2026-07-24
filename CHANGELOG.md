# Changelog

Toutes les évolutions notables de CL Audio Controller seront documentées dans ce fichier.

## [2.1.0] — 2026-07-24

### Corrigé

- Réinitialisation atomique de la télécommande lors du chargement ou du rechargement d'un Live Set.
- Identification principale du Set par `Song.file_path`, avec identité temporaire pour les Sets non enregistrés.
- Protection des traitements asynchrones et des interfaces Session, A/B et Arrangement par `set_generation` afin d'ignorer les réponses obsolètes.
- Maintien de « En cours » vide jusqu'au premier lancement réel, tandis que « Prochaine scène » suit immédiatement la sélection.
- Confirmation de l'état réel d'Ableton avant les commandes Play/Pause et suppression du délai artificiel qui pouvait rendre le bouton Session temporairement inactif.

### Interfaces

- Affichage LTC partagé dans Session et Arrangement, avec rafraîchissement fluide et sérialisé.
- Interface A/B recentrée sur le crossfader et les commandes essentielles.
- Mise en page Session et A/B compacte, adaptée à l'affichage complet sur iPhone sans défilement.
- Bouton GO placé immédiatement sous le LTC dans Session.
- Avertissement et confirmation explicite avant l'entrée en mode Arrangement.

### Intégration

- Ajout d'un patch AbletonOSC reproductible exposant en lecture seule `/live/song/get/file_path` et `/live/song/get/name`.
- Ajout de tests de non-régression pour les changements de Set, les identités temporaires et les générations périmées.
- Ajout d'un kit Max for Live transportable réunissant X-Fader, AutoScene,
  AutoScene Live 10 et LTC Remote Config, inclus séparément dans le DMG et dans
  une archive ZIP dédiée.

## [2.0.0] — 2026-07-17

### Création du dépôt autonome

- Extraction de l'application depuis `AB_Launcher_LTC_DEV` vers le workspace autonome `CL_Audio_Controller`.
- Conservation du code source, des ressources, du pont Max for Live et de la configuration PyInstaller utilisés par CL Audio Controller 2.0.0 (build 4).
- Documentation de l'environnement Python 3.14.5 et PyInstaller 6.21.0.
- Ajout d'un manifeste de dépendances reproductible et de la documentation de construction.
- Validation d'un build macOS `universal2` équivalent au bundle de référence.
- Exclusion du suivi Git des builds, distributions, applications compilées, archives et caches.

Le projet historique `AB_Launcher_LTC_DEV` reste intact et n'est pas intégré à ce dépôt.
