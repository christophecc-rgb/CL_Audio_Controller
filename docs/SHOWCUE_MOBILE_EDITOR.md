# Édition ShowCue mobile et diagnostic d’identité — 6 octobre 2026

## Cause de la fenêtre inutilisable

`templates/show_info.html` cumule les règles de hauteur de `#editor`, de scroll de `#cue-form` et de ses blocs, puis une barre `.actions` sticky. Ces contraintes suivent la fenêtre de mise en page plutôt que la zone visible lorsque Safari affiche le clavier. Des tailles de champs inférieures à 16 px favorisent aussi le zoom au focus. Voir notamment les blocs vers les lignes 1552, 1739, 1858, 10252 et 11922.

## Correction

`static/showcue-mobile-editor.js` adapte les trois éditeurs (complet, rapide et notes) à `visualViewport.height`, `offsetTop`, `width` et `offsetLeft`, avec écoute des changements de taille et de rotation. Le contenu central défile seul ; Annuler et Enregistrer restent hors de ce contenu. Supprimer est séparé en bas du contenu. Les erreurs restent près des actions. Aucune dépendance ajoutée.

`static/showcue-mobile-editor.css` impose des champs à 16 px, des boutons d’au moins 44 px, la zone de sécurité inférieure et un repli 100dvh. Les sélecteurs tiennent compte des anciennes règles prioritaires. Sur desktop, le conteneur central utilise `display: contents` et le bouton Supprimer retrouve sa place.

## Identité distante : établi et non établi

L’appareil permanent enregistré, non révoqué, porte l’identifiant `300422f726f16fea87b05c90ea093ba2`. Les droits d’édition sont présents. Les refus de PUT cue vers 22:15 et 22:17 indiquent « Appareil inconnu ou révoqué ». Les journaux historiques ne conservent ni l’identifiant réellement envoyé, ni l’origine Safari, ni la présence des quatre en-têtes. Ils ne permettent donc pas de choisir définitivement entre un appairage absent et un ancien identifiant.

L’appairage est propre à l’origine (protocole, nom/IP et port). Le code choisit sessionStorage avant localStorage. Une autre origine, un onglet ayant un ancien appairage temporaire, le stockage privé/perdu ou une ancienne version chargée sont les hypothèses restantes. Les PUT cue et notes passent bien par le fetch signé ; les tests couvrent ce chemin.

`static/remote-auth.js` fournit désormais un diagnostic de l’origine actuelle, de la disponibilité et de la provenance du stockage, de l’identifiant choisi et de la présence des quatre en-têtes X-CL. Le détail est accessible dans la barre d’état d’appairage. `security_http.py` ajoute aux seuls refus ShowCue les mêmes indicateurs côté serveur, sans modifier la décision d’autorisation. Aucun token, secret, nonce complet ou signature n’est affiché.

Après installation demandée explicitement : reproduire une sauvegarde depuis Safari, ouvrir « Diagnostic d’appairage — sans secret », comparer l’identifiant envoyé à celui ci-dessus et l’origine à celle de l’appairage. Si l’origine diffère, utiliser l’origine appairée ; si le stockage est absent ou obsolète, refaire l’appairage sur cette origine après vérification. Aucune migration ou suppression automatique des identités n’a été appliquée.

Les erreurs HTTP détaillées existantes restent conservées : statut, message/error et réponse non JSON.

## Fichiers de cette intervention

- templates/show_info.html : chargement des assets et version du script d’authentification.
- static/showcue-mobile-editor.js et .css : présentation mobile.
- static/remote-auth.js et security_http.py : diagnostic sans secret.
- tests/js/test_showcue_mobile_editor.cjs, test_remote_auth_showcue.cjs : nouveaux tests.
- tests/test_showcue_permissions.py : diagnostic des refus.

Sauvegarde ciblée avant intervention : `/private/tmp/cl-mobile-editor-before-20261006-222325`.

## Validation

90 tests Python et 6 sous-tests passent (ShowCue, permissions, sécurité, accès, transaction GO et panneau réseau). Les 22 tests HTTPS passent. Les trois suites JavaScript mobile, authentification et erreurs API passent.

La prévisualisation du formulaire réel avec zone visible réduite confirme : portrait 390×350, paysage tactile simulé 844×210, actions en grille à l’intérieur de la zone visible, champs à 16 px. La rotation et le retour desktop sont couverts par les tests JavaScript. Cela ne remplace pas un essai physique dans Safari iOS avec son clavier natif.

Nouvelle copie : `Releases/CL_Show_Control_Mobile_Editor_2026-10-06/CL Show Control.app`. Elle est reconstruite après les tests ; elle n’est pas installée. La logique MIDI/GO/Ableton/RTP et la politique de permissions restent inchangées. Aucun commit, reset ou stash.
