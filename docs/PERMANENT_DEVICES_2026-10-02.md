# Appareils temporaires et permanents — 2 octobre 2026

## Résultat

Un appareil peut être approuvé **Temporaire** ou **Permanent**. Un « iPhone Christophe » permanent en rôle operator conserve son identité, son nom, son opérateur et son autorisation après redémarrage complet du backend. Le navigateur retrouve son credential sans nouveau QR si la mémorisation a été explicitement choisie, avec la même adresse HTTPS/origine. Le système redémarre toujours **désarmé** ; aucune commande critique n'est autorisée avant armement.

Les sources uniquement ont été modifiées. Aucun bundle installé remplacé, aucun service de production lancé/arrêté, aucun commit ou reset. Aucun changement MIDI/Program Change, CL5 canal 1 / QL1 canal 2, CSV/CLF, session RTP ou transaction musicale GO/Ableton.

## Avant / après

| Aspect | Temporaire, conservé | Permanent, nouveau |
| --- | --- | --- |
| Approbation | 12 h par défaut ; 60 secondes à 24 h | Choix explicite « Permanent » |
| expires | Nombre UTC | null |
| Session runtime | Doit correspondre à celle du backend | N'invalide pas l'appareil au restart |
| Redémarrage | Autorisation temporaire expirée | Identité et clé reconnues |
| Navigateur | sessionStorage | localStorage seulement après consentement ; sinon sessionStorage |
| Critique GO / transport | Rôle autorisé + système armé + signature + anti-rejeu | Mêmes barrières |
| Révocation | Immédiate | Immédiate, même si le navigateur garde son token |
| Changement de mot de passe | Révoqué | Révoqué explicitement par politique de sécurité |

L'admin choisit le type et, pour un temporaire, sa durée en secondes dans la demande d'approbation. Le permanent affiche « Valide jusqu'à révocation ». La liste montre nom, opérateur, rôle, type, état, dernière activité, expiration éventuelle, révocation et changement de rôle. Les types ont une bordure distincte. Les choix de la demande sont conservés entre les rafraîchissements du panneau. Le renommage n'a pas été ajouté : il était facultatif dans la demande.

## Utilisation pour iPhone Christophe

1. Sur le serveur, générer le QR opérateur comme auparavant.
2. Sur l'iPhone personnel, saisir appareil/opérateur une dernière fois et cocher **Mémoriser sur cet appareil personnel si l'administrateur autorise un accès permanent**.
3. Sur le serveur, choisir **Permanent** puis **Autoriser**.
4. Le claim HTTPS à usage unique retourne l'identité et le credential ; le navigateur les mémorise sur cette origine HTTPS. Un accès approuvé temporaire ne sera jamais mémorisé en localStorage, même si la case était cochée.
5. Armer puis utiliser normalement la télécommande, sans mot de passe par GO.
6. Après redémarrage complet, rouvrir la même adresse HTTPS ou retrouver l'onglet : l'appareil permanent est reconnu. La consultation et le heartbeat fonctionnent désarmés ; réarmer pour les commandes critiques.
7. **Révoquer** coupe immédiatement ses droits. **Révoquer toutes** invalide permanents et temporaires et désarme.

## Stockage serveur et migration

`security.json` passe au schéma 2. L'identité serveur durable `server` reste conservée ; `RemoteSecurity.session` reste une identité runtime neuve à chaque lancement.

Chaque appareil conserve les champs historiques name/operator/role/id/key/expires/session/revoked/last_seen et ajoute :

- `authorization_type`: temporary ou permanent ;
- `expires`: nombre UTC pour temporary, null pour permanent ;
- `password_revision`: empreinte du dossier de hash/salt administrateur servant à invalider l'autorisation après changement de mot de passe.

Le champ session historique d'un permanent reste présent pour compatibilité/diagnostic, mais n'est pas une condition d'autorisation. L'identité durable est son id et sa clé dérivée. Le serveur stocke **SHA-256(token)**, jamais le token brut. Le token non dérivé n'existe que dans le pending en mémoire jusqu'au claim HTTPS unique et côté navigateur.

Un device historique sans authorization_type est lu comme **temporary**. Il n'est jamais promu automatiquement. Les identités, noms, opérateurs, rôles et autres champs des appareils existants sont conservés ; il n'y a aucune suppression des anciennes données. La migration du champ manquant se fait en mémoire, puis est écrite au prochain save normal. Une ancienne autorisation temporaire reste soumise à sa session/expiration.

La validité permanente exige la bonne révision de mot de passe. Un changement/reset admin révoque les deux types, y compris un permanent chargé par un autre processus/une nouvelle instance. Les sessions admin, QR et demandes runtime sont invalidés selon le comportement existant.

Les nonces récemment consommés par les appareils permanents sont persistés avec id/nonce/date d'expiration, sans secret. Cela empêche de rejouer une commande encore récente après un redémarrage rapide puis réarmement. La fenêtre de timestamp de 15 s, le cache de nonce de 30 s et la limite de 8192 entrées restent inchangés. Les données expirées ne sont pas reprises au load/save. Le fichier est écrit atomiquement en 0600 ; dossiers 0700. Chaque requête permanente acceptée persiste nonce et dernière activité, ce qui ajoute une petite écriture disque à l'autorisation distante. Une panne d'écriture refuse la requête, sans exécuter la commande musicale.

Une activité persistée n'est pas présentée comme une connexion active au redémarrage : « connecté » exige une nouvelle activité dans ce runtime. Aucun hash/secret/révision privée n'est exposé dans snapshot ; les journaux critiques conservent le format et la politique de non-divulgation existants.

## API et sécurité

`POST /security/admin/approve` conserve ses valeurs par défaut. Pour un permanent :

```json
{"request_id": "…", "authorization_type": "permanent"}
```

Pour un temporaire personnalisé :

```json
{"request_id": "…", "authorization_type": "temporary", "lifetime": 3600}
```

Le claim ajoute authorization_type, name, operator et server à sa réponse, et peut retourner expires=null. QR et claim restent à usage unique. La signature de requête et les endpoints de contrôle n'ont pas changé ; les clients historiques continuent à fonctionner pour les temporaires. Pairing HTTPS et contrôle distant sensible conservent leurs protections existantes.

Rôles toujours distincts : reader read ; operator read/show ; admin read/show/admin. La permanence n'ajoute aucune permission et ne contourne ni arm/disarm, ni révocation, ni anti-rejeu, ni maintenance admin locale. Un changement de rôle est persisté et appliqué à la prochaine requête. Le client peut garder son token après révocation, mais le serveur refuse immédiatement sa clé ; aucune action locale navigateur ne peut rétablir le droit.

## Compromis navigateur

Le choix localStorage est explicite, réservé à l'appareil personnel/fixe. Il permet de survivre à la fermeture de l'onglet et au redémarrage serveur. Ce stockage n'est pas Keychain : un script exécuté sur la même origine (notamment après une faille XSS), une extension ayant accès à cette origine, ou un accès au profil navigateur pourrait récupérer le credential. Les limites du compte/appareil et du code web restent donc importantes. La révocation serveur reste la réponse immédiate à une perte/vol.

Ne pas activer la mémorisation sur un navigateur partagé. Effacer les données du navigateur, utiliser une navigation privée, changer de profil, hostname, protocole ou port HTTPS peut nécessiter un nouveau QR. Si localStorage est bloqué, l'utilisateur est informé et le credential reste dans sessionStorage. Une permission permanente serveur sans mémorisation navigateur reste valide dans cet onglet, mais ne permet pas de retrouver un secret perdu à sa fermeture. Aucun token n'est placé dans une URL ou un journal. Keychain n'a pas été intégré.

## Fichiers, sauvegarde et vérifications

Fichiers modifiés :

- remote_security.py : format/migration, approbation, validité, rôle, révocation, persistance nonces et activité ;
- security_http.py : transmission du type d'approbation, uniquement cette ligne ;
- static/remote-pair.html et static/remote-pair.js : consentement et stockage selon type ;
- static/remote-auth.js : reprise d'un permanent mémorisé, signature inchangée ;
- static/security-panel.js : choix temporaire/permanent, durée et liste détaillée.

Créations : tests/test_permanent_devices.py, tests/js/test_permanent_credentials.cjs et ce document. Les tests Phase 2 existants sont inchangés.

Sauvegarde : `backups/permanent-devices-20261002-113540/`. Originaux des six fichiers copiés avant édition ; manifest avec SHA-256, diff `task-only.diff`, liste de fichiers et rapports. Les hashes prouvent aussi l'absence de modification de app.py, launcher_control.py et tools/cl_midi_network/CLMIDINetworkDashboard.m. Le correctif `run_embedded_server()` → `module.start_remote_tls(module.app)` avant app.run et le lifecycle de fermeture Objective-C sont conservés intégralement.

Résultats :

- **52 tests Python ciblés passent**, incluant tous les tests Phase 2 sécurité/rôles/backup et 19 nouveaux tests de permanence ;
- **6 tests JavaScript navigateur passent**, exécutant les vrais scripts avec stockage et WebCrypto ;
- suite élargie : **223 réussites, 21 échecs, 3 subtests réussis** ;
- contrôle avant tâche avec modules originaux sauvegardés : **204 réussites, les mêmes 21 échecs, 3 subtests réussis** ; aucune nouvelle régression détectée ;
- py_compile et syntaxe des trois scripts JavaScript passent ;
- `git diff --check` signale uniquement la ligne blanche déjà présente dans packaging/INSTALLATION_NOUVEAU_MAC.txt, fichier non modifié par cette tâche.

Les 21 échecs préexistants concernent les assertions historiques Network Manager/outillage MIDI, un test de désinstallation MIDI et un ancien marqueur du panneau launcher. Les identifiants complets figurent dans baseline-results.txt et regression-results.txt ; leurs ensembles d'échecs sont comparés automatiquement.

Tests isolés : Path.home remplacé par un dossier temporaire ; fichiers de sécurité temporaires ; UDP Phase 2 seulement sur lo0/port éphémère. Le contrôle baseline charge les originaux sauvegardés, sans restaurer ou réécrire les sources du dépôt. Aucun build complet n'a été nécessaire ni effectué : l'intégration ne change pas les entrées du bundle ou ses dépendances.

## Validation manuelle restante sur un build de test

1. Reconstruire un bundle de validation sans remplacer la production ; utiliser un dossier de sécurité et des données de test distincts.
2. Appairer iPhone Christophe/operator en Permanent, cocher la mémorisation ; contrôler le nom, le rôle et « Valide jusqu'à révocation » dans le panneau.
3. Fermer/réouvrir l'onglet et redémarrer complètement Show Control/backend. Vérifier heartbeat et nom conservés sans QR, système désarmé et GO refusé. Armer, vérifier commande autorisée dans un environnement musical de test.
4. Révoquer depuis l'admin, vérifier le refus immédiat avec le token encore présent dans le navigateur ; refaire l'essai avec Révoquer toutes.
5. Tester un temporaire 60 s, un temporaire 12 h, lecture seule permanente, changement de rôle et reset admin local : les anciennes clés doivent être refusées selon les règles ci-dessus.
6. Vérifier qu'un navigateur sans mémorisation/privé affiche le compromis et ne promet pas une reconnexion persistante.

Cette tâche n'a pas exécuté ces manipulations sur un téléphone réel ou les applications de production. Le fonctionnement TLS/QR du bundle validé précédemment par l'utilisateur est conservé ; la nouvelle permanence est validée automatiquement côté serveur et navigateur, et reste à confirmer sur ce build de test.
