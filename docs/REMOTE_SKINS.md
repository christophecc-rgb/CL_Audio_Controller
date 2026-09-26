# Design commun Session / A-B / Arrangement

Dans chaque page, ouvrir **Options avancées → Apparence** : Original, Broadcast, Theatre ou Show Control. Le choix s'applique immédiatement, persiste au rechargement et suit la navigation entre les trois pages. Les onglets ouverts sont synchronisés par l'événement de stockage. Aucun appel de commande ne provient du changement de skin.

Original conserve le rendu fonctionnel présent avant cette refonte globale. Les nouveaux headers sont transparents à la mise en page d'origine, et les timers/badges ajoutés sont masqués. Pour revenir au rendu précédent, sélectionner Original. La navigation commune et le sélecteur restent disponibles.

## Composants

Les trois templates contiennent réellement les mêmes composants : `sc-card`, `sc-current`, `sc-next`, `sc-card-header` / `current-card-header`, `sc-role`, `sc-time` / `current-card-timer`, `sc-time-label`, `sc-title`, `sc-source-time`, `sc-card-footer`, `sc-state-badge` / `current-state-badge`, `sc-channel`, `sc-go-feedback`. Arrangement ajoute `sc-conduite` et `sc-locator` à ses groupes existants.

Les identifiants métier, notamment `currentCard`, `current` et `currentTimer`, sont conservés. Les trois scripts métier intégrés aux templates sont inchangés. Le timer d'origine reste la source ; son affichage est projeté dans le header sans recalcul ni nouvelle horloge. Les données `data-ui-state` et `data-ui-deck` servent uniquement au rendu.

Les variantes partagent géométrie, hiérarchie, contrôles et états dans `static/remote-v2.css`. Broadcast utilise le graphite sobre ; Theatre des tons chauds et une typographie de titre serif ; Show Control des tons bleutés et des séparateurs plus nets. Aucune image de fond ne remplace l'interface.

## États et feedback

- Cartouche actuelle : PLAYING, PAUSE, STOPPED, CONNEXION, HORS LIGNE. Accent latéral et pulse discrets ; aucun grand aplat lumineux dans les variantes modernes.
- Carte suivante : SELECTED, READY, IMMINENT selon les classes existantes. L'imminence reste propre à A/B. Pas d'état métier inventé.
- A/B : deck A, B ou mix identifié depuis le retour affiché ; la pause/lecture vient de l'état accepté, car la classe historique peut mémoriser un lancement.
- GO : retour bref d'appui (il ne signifie pas confirmation serveur), plus feedback de rappel Session existant. Changement de titre : transition discrète.
- MIDI : idle, waiting, confirmed, loaded (confirmation mémorisée), mismatch, timeout. Les moteurs et durées restent identiques ; les calques modernes sont limités à un accent au bord de la cellule.
- LTC connecté/déconnecté conservé sur les pages qui le possèdent. A/B ne reçoit aucun composant MIDI/LTC artificiel.

La préférence globale est `cl-audio-global-skin-v1`, migrée depuis `cl-audio-session-skin-v1` si nécessaire. Valeur invalide : Original. Stockage indisponible : choix pendant la visite. L'ancienne préférence historique n'est pas supprimée.

## Fichiers de cette refonte globale

Modifiés : `templates/index.html`, `templates/ab.html`, `templates/arrangement.html`, `static/remote-v2.css`, `static/cl-skins.js`, `static/skins/skin-switcher.js`, `static/skins/broadcast.css`, `static/skins/theatre.css`, `static/skins/show-control.css`, `tests/js/test_session_skins.cjs`, `docs/REMOTE_SKINS.md`.

Ajoutés : `static/skins/presentation.js`, `tests/js/test_remote_design_system.cjs`, `tests/js/render_remote_fixture.py`.

`static/skins/original.css`, `app.py`, `static/remote-v2.js`, `static/midi-return-visual.js`, `static/cl-skins.css` restent inchangés pendant cette étape. Aucun commit, reset ou push.

## Vérification hors ligne

Exécuter `node tests/js/test_remote_design_system.cjs` avec Playwright installé. Variables facultatives : `PLAYWRIGHT_MODULE`, `CHROME_PATH`, `SKIN_TEST_OUTPUT`. L'ancien point d'entrée `test_session_skins.cjs` lance aussi cette suite commune.

Le banc extrait uniquement la fonction de décoration HTML de `app.py` par AST ; il n'importe ni ne lance le serveur. Toutes les requêtes sont interceptées localement. 84 combinaisons : trois vues, quatre skins et sept formats (1440×900, 1024×768, 768×1024, 390×844, 320×568, 844×390, 667×375). Il contrôle lecture/pause/stop, préparation, imminence A/B, deck, connexion, six classes MIDI, LTC, absence d'aplat lumineux, absence de débordement horizontal, headers/badges visibles, dimensions des boutons, préservation des identifiants et navigation avec préférence globale. Les états MIDI sont injectés pour ce contrôle de présentation ; le moteur est vérifié séparément par `node tests/js/test_midi_return_visual.js`.

Les captures desktop et mobiles sont inspectées en complément. Ces tests Chromium simulés ne remplacent pas une validation Safari sur iPhone réel ni une répétition avec Ableton, consoles et LTC physiques.

Une sauvegarde avant cette étape, `sauvegarde-avant-refonte-globale.zip`, est livrée avec le rapport. Pour une restauration complète manuelle, restaurer les fichiers de cette étape depuis cette sauvegarde et retirer les trois fichiers ajoutés, après préservation d'éventuelles modifications ultérieures. Le choix Original suffit pour revenir visuellement au design précédent.
