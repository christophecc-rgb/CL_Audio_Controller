# Contrôle effectif des commandes Remote

## Cause reproduite

Le lanceur 5055 et le backend 5050/8443 possèdent deux instances `RemoteSecurity`.
Le backend utilise `security.json`, le lanceur `launcher-security.json`.
L'ancien POST `/security/admin/arm` du lanceur modifiait uniquement l'état du
lanceur, qui ne sert pas les commandes iPhone. Le backend restait armé.

En parallèle, `/security/status` omettait `devices` quand l'administration était
verrouillée. Le front assimilait cette omission à une liste vide. Une liste
masquée était donc présentée comme « Appareils appairés (0) ».

L'inspection en lecture seule du serveur installé a confirmé un administrateur
permanent dans le registre backend, aucun appareil dans celui du lanceur, et
un backend armé. Aucun GO/STOP réel n'a été envoyé pendant l'analyse.
Les cookies historiques ne constituent pas un bypass de `/action` : le chemin
reproduit est un désarmement sur le mauvais serveur et un comptage trompeur.

## Routes et protections

| Route | Actions | Contrôle serveur distant |
| --- | --- | --- |
| POST `/action` | GO, STOP, PREV, NEXT, pause/play, goto, transport Arrangement, crossfader | Appareil enregistré, autorisation valide, rôle commande, permission spécifique, armement, HMAC/nonces/horodatage |
| POST `/action` | `console_title_mode`, `console_title_offset` | Même contrôle, plus rôle admin, HTTPS, mode configuration et déverrouillage local |
| POST `/transport/test`, `/show-audio/print/capture-clean` | Test transport / capture pilotée | Rôle de commande + armement et signature |
| POST `/show-audio/offline/live-loop`, `/show-audio/tracks-mute` | Réglages audio/Live | Contrôle admin + armement et signature |
| PUT/POST/DELETE `/show-info/cues`, `/show-info/cues/<id>`, PUT notes par poste | Édition ShowCue | Grants explicites, rôle commande, HTTPS, armement et signature ; scope des postes conservé |
| POST `/show-info/call`, ack/cancel, capture, audio ; autres mutations ShowCue/builder/sessions | Mutations ShowCue | Contrôle admin existant + armement et signature |
| GET/POST `/rescan-scenes`, `/build-show` ; POST paramètres/backup | Mutations de configuration | Contrôle admin ; GET n'est pas une exemption pour ces routes |
| GET ShowCue/status/pages et audio de cues | Lecture | Lecture publique existante conservée, indépendante du désarmement |
| POST `/remote/heartbeat` | Présence / permissions | Signature de l'appareil, droit lecture ; aucune commande musicale |
| `/remote/pair/*`, trust/check/verify | Appairage et confiance TLS | Contrôles propres aux routes ; aucune commande musicale |
| `/security/admin/*` | Administration | Administration locale uniquement ; cookies backend/lanceur séparés |

Session, Arrangement et les actions ShowCue qui pilotent le transport utilisent
POST `/action`. `remote-v2.js` utilise également cette route pour le retour en
Arrangement. Il n'existe pas de canal WebSocket ou de token legacy permettant
à ces pages de lancer les commandes hors de la frontière Flask.

## Authentification existante

- `cl_admin_backend` / `cl_admin_launcher`, ou `X-CL-Admin` : déverrouillage local
  d'administration, jamais une identité d'appareil distant.
- `cl-paired-device-v1` dans sessionStorage/localStorage : identifiant + secret
  d'appareil utilisé pour signer les requêtes. Le secret seul ou un Bearer token
  n'autorise pas les commandes.
- Registre backend : hash de clé, rôle, révocation, durée/session temporaire ou
  autorisation permanente liée à la révision du mot de passe.
- QR à usage unique + demande + approbation locale + claim : acquisition d'une
  identité enregistrée. Aucun ancien token absent du registre n'est migré en admin.
- Le seul accès de confiance est le véritable loopback du Mac avec Host/origine
  locaux. Les en-têtes `X-Forwarded-*` ne confèrent pas cette confiance au LAN.

## Correction

Le POST armement sur le lanceur délègue désormais au proxy backend existant.
Il conserve l'authentification backend : un déverrouillage du lanceur seul ne
suffit pas. Un backend absent ou refusant l'opération ne produit pas un succès.
Les mutations d'appareils sur le registre lanceur sont refusées (409).

La page `/security/panel` du lanceur redirige côté serveur vers la vraie page
backend. `/security/maintenance` conserve la maintenance locale distincte.
Le statut local backend fournit un comptage explicite même quand les détails
sont masqués ; le front distingue une liste verrouillée d'une liste vide.

`authorize` exige explicitement un rôle admin/opérateur pour toute permission
hors lecture. Une commande distante est refusée avant son handler si l'identité,
la signature, le rôle ou l'armement manque. Le registre et l'armement sont vérifiés
à chaque requête : désarmer affecte la prochaine commande d'une page déjà ouverte ;
réarmer ne demande pas de réappairage. Aucune annulation rétroactive d'une commande
déjà exécutée n'est introduite. Le lecteur reste sans GO/STOP/édition, armé ou non.

Les tests reproduisent les deux bugs, vérifient la non-exécution des handlers
refusés, tous les transports Remote, les cookies/tokens historiques, le rôle
lecteur, les changements de rôle/révocation et le routage backend de l'armement.
Aucun fichier de sécurité utilisateur, TLS, QR ou moteur musical n'est modifié
par les tests. Le correctif du dépôt nécessite un chargement de ce code par
l'application installée ; il ne remplace pas à chaud le processus actif.
