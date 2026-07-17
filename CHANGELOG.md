# Changelog

Toutes les évolutions notables de CL Audio Controller seront documentées dans ce fichier.

## [2.0.0] — 2026-07-17

### Création du dépôt autonome

- Extraction de l'application depuis `AB_Launcher_LTC_DEV` vers le workspace autonome `CL_Audio_Controller`.
- Conservation du code source, des ressources, du pont Max for Live et de la configuration PyInstaller utilisés par CL Audio Controller 2.0.0 (build 4).
- Documentation de l'environnement Python 3.14.5 et PyInstaller 6.21.0.
- Ajout d'un manifeste de dépendances reproductible et de la documentation de construction.
- Validation d'un build macOS `universal2` équivalent au bundle de référence.
- Exclusion des builds, distributions, applications compilées, archives et caches du futur historique Git.

Le projet historique `AB_Launcher_LTC_DEV` reste intact et n'est pas intégré à ce dépôt.
