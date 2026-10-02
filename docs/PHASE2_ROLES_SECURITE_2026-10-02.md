# Phase 2 — rôles, transports, télécommandes et backup

Travail dans les sources du dépôt, sans commit, reset, installation en production ni modification des CSV/CLF, sessions RTP, mappings CL5/QL1 ou logique MIDI/Program Change. Les changements précédents de l'utilisateur sont conservés. Les fonctions `execute_go_transaction`, `send_midi_monitor_scene_context`, `record_go_midi_expectations`, `stop_owned_server`, `start_console_simulator` et `stop_owned_child` sont identiques, par comparaison AST, aux sauvegardes prises au début de cette phase.

## État de la phase 1 et limite préalable

Les corrections lifecycle/moniteur/UDP sont présentes dans les sources et leurs tests passent. Elles n'ont pas été validées ici dans un bundle reconstruit avec Cmd-Q, Cocoa, changement d'interface ou applications musicales réelles. Aucun service de production n'a été arrêté ou lancé.

Le code de CL Show Backup est absent du dépôt. La phase 2 fournit un récepteur UDP embeddable et le protocole HMAC ; elle ne prétend pas avoir modifié l'application externe. L'installation du rôle backup refuse de continuer sans composant externe et validation de son intégration (`SCENE_BACKUP_HMAC_RX_VALIDATED` dans le kit, à ajouter uniquement après les essais réels TX/RX).

## Architecture par rôle

Source de vérité : `config/installation_roles.json`. Le moteur `packaging/role_install.py` produit le manifeste complet, l'audit et les opérations symétriques. Une machine possède un rôle principal et des options explicitement sélectionnées.

| Rôle | Composants par défaut | Transports | Services permanents |
| --- | --- | --- | --- |
| `show_server` | Show Control : launcher/backend/bibliothèques/TX ; Network Manager et helpers de diagnostic | HTTP, OSC, Scene Backup, Bonjour | Aucun LaunchAgent ajouté ; moniteur possédé par launcher |
| `ableton_reader` | AbletonOSC, devices LTC/X-Fader, CL Absolute MTC | OSC, MTC, Bonjour | Aucun ; agent RTP en option `rtp` |
| `mtc_logic` | CL MTC Bridge, Sync Meter | MTC | Aucun ; applications ouvertes explicitement |
| `control_station` | CL Show Control Client, navigateur vers Show Control/ShowQ/ShowCue serveur | HTTPS ; Bonjour facultatif | Aucun backend, helper ou daemon de production |
| `show_backup` | CL Show Backup externe, AbletonOSC local | UDP Scene Backup, OSC local | Aucun RTP implicite |
| `diagnostics` | Network Manager, helpers/simulateurs, Analyzer, Performance Monitor, MIDI & RTP Diagnostic | Transports testés explicitement | Aucun |
| `custom` | Liste explicite parmi les composants du catalogue | Selon les composants sélectionnés | Seulement services des composants explicitement sélectionnés |

Le lecteur peut sélectionner `mtc_bridge` en option. RTP est refusé comme option des rôles serveur, contrôle, backup ou diagnostic ; l'installation personnalisée peut sélectionner son composant explicitement. Son propriétaire reste launchd. Le moteur RTP et les sessions musicales n'ont pas été réécrits.

Le manifeste inclut composants, services requis/interdits, permissions macOS, transports, ports, dépendances, outils visibles et détails de chaque composant. Les outils et rôles sont exposés dans l'interface native de l'installateur et du désinstallateur. Le démarrage historique du pont MTC passe désormais par le vrai lancement de Show Control, jamais un import Python ; un manifeste de rôle empêche son autostart s'il n'est pas sélectionné. Sans manifeste, le comportement historique est conservé.

Les rôles serveur/contrôle/MTC/diagnostic n'imposent pas Live. Les extensions Ableton exigent Live 11/12 ; les devices exigent Max for Live. Le moteur vérifie les sources et, dans un kit exporté, leurs empreintes avant remplacement. Python 3.9+ est une dépendance explicite du moteur d'installation, sélectionnable par `CL_SUITE_PYTHON` pour les wrappers. Les applications Show Control embarquent leur runtime Python. Les chemins de Live atypiques utilisent `CL_SUITE_LIVE_APPS` et `CL_SUITE_USER_LIBRARY`. `CL_SUITE_ASSUME_M4L=1` est une confirmation explicite de licence, jamais une détection implicite.

## Responsabilités et ports

| Transport | Responsabilité | Ports principaux |
| --- | --- | --- |
| Bonjour/mDNS | Découverte uniquement ; aucune autorisation ou changement implicite de cible | UDP 5353 ; publications existantes conservées |
| HTTP | Backend/API sur 5050 ; panneau local sur 5055 | TCP 5050 ; 5055 loopback |
| HTTPS | Appairage et télécommande sur listener supplémentaire | TCP 8443 par défaut, configurable |
| AbletonOSC | Commandes Ableton et retours | UDP 11000/11001 ; devices 9001/9002 |
| RTP-MIDI | MIDI réseau, si rôle/option le nécessite | CoreMIDI selon sessions existantes ; agent 50021/50022 ; feedback 50023 |
| MTC | Synchronisation temporelle | UDP 20809/20810 loopback ; IAC CL MTC |
| Scene Backup | Scène uniquement ; ping/pong pour preuve de lien | UDP 12042 unicast |
| LTC existant | Retour temporel existant, inchangé | UDP 63123 |

Le panneau affiche HTTP, OSC, RTP, MTC, Bonjour, BACKUP LINK et REMOTE CONTROL séparément. HTTP est l'état du serveur ayant répondu. OSC reprend le diagnostic réel d'OSCTransport. RTP et MTC affichent `UNKNOWN` tant qu'une télémétrie distincte ne fournit pas de preuve : leur intégration complète aux outils natifs reste à faire, aucun voyant vert artificiel. Une découverte Bonjour n'autorise jamais GO. Le tunnel backup n'appelle ni RTP, ni OSC, ni Bonjour ; aucun fallback de secours n'est ajouté.

## Administration locale

Panneau backend : `http://127.0.0.1:5050/security/panel`. Le launcher propose un lien clair vers cette gestion. Son propre panneau sur 5055 gère l'administration de maintenance du launcher, pas les appareils du backend. Les sessions administrateur des deux processus sont distinctes ; le mot de passe est partagé. Cela évite d'attribuer l'armement du launcher à celui du backend. Déverrouiller les deux lorsque la maintenance touche les deux processus.

Première configuration locale : mot de passe d'au moins 12 caractères. Stockage scrypt N=32768/r=8/p=1, salt aléatoire de 32 octets. Fichiers privés 0600 et nouveaux dossiers 0700, sans mot de passe en clair. Cinq échecs imposent cinq minutes d'attente. Les sessions administrateur sont en mémoire, expirent après cinq minutes et utilisent des cookies HttpOnly/SameSite=Strict distincts par service. Un changement de mot de passe invalide les sessions, désarme et impose de nouvelles prises de poste. Aucun secret n'est retourné dans l'état.

Keychain n'est pas intégré dans cette V1 : le hash vérifiable privé est partagé entre les deux processus, sans mot de passe réversible ni nouvelle dépendance native. La sécurité contre un utilisateur ayant déjà accès au même compte macOS reste celle du compte et du disque.

MODE SPECTACLE bloque les changements sensibles. Le mot de passe local permet de passer en MODE DÉVELOPPEMENT/INSTALLATION ; ce mode garde les signatures, permissions, armement et journaux. Revenir en spectacle puis verrouiller avant exploitation. GO local reste inchangé ; GO distant ne reçoit aucune exception de développement.

Mot de passe oublié : depuis un terminal local interactif sur le serveur, lancer le binaire Show Control avec `--reset-admin-password`, ou `python3 security_recovery.py` depuis le dépôt. Confirmation `RESET`, saisie masquée et confirmation du nouveau mot de passe. Aucun endpoint de reset distant. Les télécommandes sont révoquées/désarmées après changement. Ne pas lancer cette récupération pendant un spectacle.

Références : [scrypt dans Python](https://docs.python.org/3/library/hashlib.html#hashlib.scrypt) ; [génération QR SVG, qrcode 8.2](https://pypi.org/project/qrcode/8.2/).

## HTTPS et QR / prise de poste

1. Installer un certificat correspondant au nom serveur et reconnu par les téléphones. Utiliser une autorité déjà reconnue ou une autorité locale installée et approuvée sur les appareils ; un simple certificat inconnu ne suffit pas pour une UX sans alerte.
2. Dans le panneau backend local, déverrouiller puis activer le mode développement. Configurer certificat PEM, clé privée avec permissions 0600, port HTTPS et URL publique. La configuration TLS privée est persistée, la clé privée reste dans son fichier local. Redémarrer le backend et vérifier l'adresse HTTPS avant génération du QR. Les variables `CL_REMOTE_TLS_CERT`, `CL_REMOTE_TLS_KEY`, `CL_REMOTE_TLS_PORT` et `CL_REMOTE_PUBLIC_URL` restent des overrides explicites de développement.
3. Générer un QR opérateur, lecture ou admin. L'adresse serveur est renseignée par l'administrateur à l'installation ; l'opérateur n'a pas à connaître IP, port ou URL.
4. Le QR porte un code aléatoire à usage unique, expirant en 120 secondes, lié au serveur et à la session. Il est placé dans le fragment de l'URL, absent des accès HTTP, puis effacé de l'historique par la page d'appairage. Le mot de passe administrateur n'est jamais dans le QR. Le QR admin exige le déverrouillage local et n'est jamais affiché en permanence.
5. Le téléphone indique appareil/opérateur. La demande apparaît sur le serveur ; l'administrateur approuve. Le code a déjà été consommé, aucune seconde demande avec ce QR.
6. Le téléphone réclame son identité et son token une seule fois, via HTTPS et une clé de réclamation temporaire. Approbation valable 12 heures par défaut (API : de 60 secondes à 24 heures), expirant également au redémarrage du backend.
7. Lecture ouvre ShowQ ; opérateur ouvre la télécommande. Armer les télécommandes lorsque les postes sont prêts. L'usage musical normal ne redemande pas le mot de passe.

Permissions V1 : `reader` = read ; `operator` = read/show ; `admin` = read/show/admin. Les opérations de configuration d'un appareil admin exigent aussi HTTPS, armement et une fenêtre de maintenance ouverte localement. La gestion de sécurité elle-même reste locale : une télécommande admin ne peut pas s'octroyer un déverrouillage serveur ni réinitialiser son mot de passe.

Le token navigateur reste dans sessionStorage, pas dans une URL ou un journal. Fermer la session de navigation peut nécessiter un nouvel appairage. Les requêtes utilisent SHA-256(token) comme clé HMAC, puis signent méthode, chemin/query, hash du corps, timestamp et nonce aléatoire. Fenêtre de 15 secondes, cache de doublons de 30 secondes. Changer le corps, chemin ou commande invalide la signature. Les tokens révoqués/expirés et les anciens nonces sont refusés. L'état désarmé refuse les commandes critiques mais laisse la consultation et le heartbeat fonctionner.

Les GET historiques qui déclenchent des actions sont protégés également ; les routes mutantes inconnues requièrent la permission admin. Les consultations usuelles restent ouvertes sur le LAN en V1. Le contrôle local loopback reste utilisable : IP loopback, Host local et contrôle Origin/Fetch-Site, sans confiance dans des headers de proxy.

DÉSARMER TOUTES ne coupe pas le backend. Révoquer un appareil efface sa clé ; révoquer tous invalide également les QR/demandes et désarme. Les journaux privés `commands.jsonl` contiennent date, appareil, opérateur, rôle, commande, scène, résultat et raison. Ils ne contiennent pas mots de passe, secrets HMAC ou tokens.

## Scene Backup signé et réseau dédié

Le mode historique `legacy_v1` est conservé comme migration explicite, affiché `LEGACY UNVERIFIED`, jamais comme lien authentifié. Le TX démarre désactivé. La V1 historique ne doit pas être utilisée comme secours sécurisé.

Le panneau local permet d'activer `hmac_v1` avec show, session, secret partagé (32 caractères minimum ; générateur 32 octets aléatoires), IP locale dédiée, nom de l’interface (par exemple en7) et IP RX explicite. Le socket se lie à l’adresse source et à l’interface (IP_BOUND_IF sur macOS) ; une interface absente échoue sans basculer sur l'interface par défaut. Adresses IPv4 uniquement ; multicast, unspecified et broadcast sont refusés. Par prudence, .0/.255 sont exclus même sur des sous-réseaux où ils pourraient être des hôtes ; utiliser des adresses ordinaires et un sous-réseau isolé correctement configuré. Aucun DNS, broadcast, multicast ou découverte automatique dans ce tunnel.

Paquet scène : `v/show/session/seq/scene/ts/auth`. HMAC-SHA256 sur JSON canonique trié, UTF-8, sans espaces, champ auth exclu. Timestamp UTC, âge maximal 0,5 seconde par défaut. Le RX épingle le show et la session configurés localement, vérifie HMAC, âge, séquence croissante et IP source éventuelle. Trois copies identiques n'exécutent qu'une scène. Le secret n'apparaît jamais dans le paquet, état ou journal.

Des ping/pong signés distincts des paquets scène prouvent la présence du récepteur ; ils ne peuvent pas lancer une scène. Le TX affiche BACKUP LINK OK uniquement après réponse signée depuis le peer/port configuré ; DOWN après trois secondes sans réponse. Une file bornée, l'expiration de 0,5 seconde et les epochs de configuration/session suppriment les événements périmés. Aucun GO perdu n'est réémis lors de la reconnexion.

`scene_backup_receiver.SceneBackupUDPReceiver` est embeddable : fournir IP bind RX et source_interface pour le réseau dédié, show/session/secret, source TX autorisée et callback `on_scene` vers le lancement local existant. Il ne modifie pas l'orchestration ou les mappings. Ne pas ajouter directement un nouveau chemin musical sans intégrer et tester ce callback dans l'application externe.

Rotation : arrêter le tunnel à l'arrêt du spectacle, générer un nouveau secret ET une nouvelle session, configurer les deux côtés localement, réactiver puis attendre LINK OK. Le RX abandonne immédiatement l'ancienne session/clé : aucune grâce acceptant de vieux GO. Horloges des deux machines à synchroniser avant spectacle. La configuration TX reste volatile comme en phase 1 ; il faut la remettre après redémarrage, puis armer explicitement. Aucun secret de backup n'est persisté en clair par cette phase.

## Migration, installation et désinstallation

Faire les premières installations sur un compte/Mac de test et reconstruire les bundles depuis ces sources. Ne pas réutiliser un vieux bundle pour tester le code de phase 2.

1. Quitter Show Control proprement. Le moteur refuse le remplacement/retrait du serveur local si 5050/5055 sont encore ouverts ; il ne tue pas un serveur inconnu.
2. Choisir le rôle dans le nouvel installateur. Il audite apps connues, anciens alias, backups .backup/.sauvegarde, deux anciens LaunchAgents et chemins du manifeste historique admissibles. Les configurations et CL_Transport sont signalés et conservés.
3. Choisir **Migrer**, **Supprimer anciens composants** ou **Conserver**. Migrer/retirer déplace les anciens composants non requis dans une Corbeille horodatée et retire uniquement les services CL connus correspondants. Les deux choix ont la même politique de conservation des données. Conserver ne retire rien ; `validate` signale les anciens composants/services incompatibles et retourne une validation non conforme, jamais un succès silencieux.
4. Installer et valider. Le manifeste privé enregistre rôle, options, chemins, audit et conservation des configurations. Les anciennes versions et le manifeste précédent restent récupérables. Choisir explicitement RTP si requis sur le lecteur ; aucune session RTP de production n'est configurée par le moteur.
5. Initialiser admin/TLS, réappairer les clients historiques, configurer le backup signé après mise à jour RX. Les clients qui ne savent pas signer restent lecteurs ; ils ne gardent pas un droit GO basé sur le LAN. Les profils Local/Paradis/Distant et leurs cibles restent conservés. Pour les anciennes fenêtres natives sans appairage, utiliser le client navigateur HTTPS appairé jusqu'à leur migration.
6. Désinstaller avec le même rôle. Les options installées sont relues du manifeste : un RTP optionnel ne reste pas orphelin parce qu'une option a été oubliée au retrait. Les composants vont à la Corbeille ; configurations, bibliothèques et journaux privés sont conservés et documentés. Une réinstallation peut les reprendre ; mot de passe partagé et nouveaux appairages restent à vérifier.

Exemples depuis le dépôt (adapter `--kit` vers un kit exporté contenant Composants ; `plan/audit/validate` n'installent rien) :

```sh
python3 packaging/role_install.py plan show_server
python3 packaging/role_install.py audit show_server
python3 packaging/role_install.py install show_server --kit /chemin/Composants --migration migrate
python3 packaging/role_install.py validate show_server
python3 packaging/role_install.py install ableton_reader --features rtp --kit /chemin/Composants --migration keep
python3 packaging/role_install.py install control_station --server-url https://serveur.local:8443 --migration migrate
python3 packaging/role_install.py uninstall ableton_reader
python3 packaging/role_install.py install custom --components network_manager,analyzer --kit /chemin/Composants --migration migrate
```

Les wrappers `.command` utilisent `CL_SUITE_ROLE` pour ce moteur. Les anciennes sélections `CL_SUITE_COMPONENTS`/`CL_SUITE_UNINSTALL_COMPONENTS` restent dans leurs chemins historiques, explicitement séparées : elles ne prétendent pas fournir la validation par rôle. Ne pas les utiliser pour une nouvelle installation par rôle. Les configs conservées ne sont pas automatiquement effacées après désinstallation ; c'est volontaire et indiqué dans `role-uninstalled.json`.

## Fichiers et sauvegardes

Sauvegarde pré-phase 2 : `backups/phase2-20261002-014003/`, originaux copiés avant modification, empreintes et diff limité à cette phase. Inclut les fichiers modifiés tardivement (requirements, ShowQ et tests). Ce diff évite de confondre les modifications préexistantes de l'utilisateur avec la phase 2.

Créations : manifeste JSON ; moteur rôle ; modules `remote_security`, `security_http`, `security_recovery`, `scene_backup_protocol`, `scene_backup_receiver` ; trois pages/scripts sécurité/appairage/auth navigateur ; tests de rôle/sécurité/backup ; ce document.

Intégrations : app.py ; launcher_control.py ; scene_backup_udp.py ; spec PyInstaller ; requirements ; quatre templates index/AB/Arrangement/ShowQ ; installateur/désinstallateur modernes ; UI native ; export du kit ; tests server_identity/network_target_independence/packaging adaptés à l'authentification et aux rôles.

## Tests automatisés et limites

Derniers résultats : **72 tests ciblés passent** ; suite élargie **203 passent, 21 échouent déjà avant cette phase, 3 subtests passent**. Les 21 échecs portent sur les assertions historiques du dashboard/outillage MIDI, un test de désinstallation MIDI et un marqueur ancien du panneau launcher ; voir le rapport de phase 1 pour la reproduction avant changements. Résultats exacts dans la sauvegarde (`phase2-regression-results.txt`, `phase2-targeted-results.txt`). Tests isolent Path.home et les configs dans des dossiers temporaires. Les échanges UDP réels utilisent exclusivement des IP loopback et un port éphémère.

Couverts : sept rôles, services par défaut absents, RTP opt-in et retrait symétrique, dépendances/préflight, migration conservant config, password hash/salt/permissions, partage entre processus/reset, sessions/verrouillage/modes, QR TTL/single-use/approbation/claim, rôles/armement/révocation/expiration/signature/rejeu, boundary Flask, refus GO anonyme, configuration TLS, HMAC scène/âge/session/source/rotation, probes signés, coupure/reconnexion sans replay, absence de fallback/interface, isolation des transports, phase 1 lifecycle/ownership/simulateurs et indépendance des cibles réseau. Compilation Python, JavaScript, shell et syntaxe Objective-C vérifiées.

Non exécutés : export complet/reconstruction/signature des bundles ; UI native interactive ; certificat réel sur iOS ; Live/Logic/CoreMIDI/macOS permissions ; gestion réelle de launchd ; câble Ethernet physique ; intégration et scène musicale dans CL Show Backup externe. Aucun test ne vaut validation spectacle sur les deux machines.

Risques résiduels : certificat/horloges/noms d’interface ; clients historiques à migrer ; télémétrie RTP/MTC encore UNKNOWN dans le panneau unifié ; configuration backup volatile ; audit limité aux composants CL connus, pas aux anciens jobs arbitraires ; absence de rollback transactionnel complet si panne disque ou copie interrompue après préflight (auditer/réparer avant reprise) ; protection du compte macOS/disque ; aucun audit de pénétration ni durcissement complet du serveur HTTP réalisé. Une configuration erronée du callback externe pourrait modifier le comportement du secours : validation musicale obligatoire, hors modifications de cette phase.

## Checklist manuelle avant exploitation

1. **Serveur Show Control** : installer le rôle sur compte de test, validate OK, aucun LaunchAgent moniteur/RTP ajouté ; démarrer/quitter par fenêtre et Cmd-Q, contrôler que backend/moniteur/pont possédés s'arrêtent. Confirmer les bibliothèques consoles inchangées.
2. **Lecteur Ableton** : installer sans option RTP ; vérifier uniquement AbletonOSC/devices, aucun agent. Ajouter RTP seulement si nécessaire et vérifier un seul propriétaire launchd, sans modifier sessions ni mappings. Test OSC avec cibles conservées.
3. **MTC/Logic** : installer MTC Bridge/Sync Meter, ouvrir explicitement, choisir CL MTC IAC et vérifier le flux ; aucun backend 5050/5055 ou RTP automatique.
4. **Poste contrôle** : installer client vers HTTPS ; vérifier absence backend/agent/helper de production ; lecture du serveur, appairage puis commandes selon rôle.
5. **Backup câblé** : intégrer RX externe, IP TX/RX dédiées, mêmes show/session/secret, allowed_source TX ; LINK OK, GO unique malgré trois copies. Mauvais secret/session/source/paquet ancien refusé. OSC local du secours reste un transport distinct.
6. **Téléphone opérateur** : certificat accepté, QR op scanné sans saisir URL, attente admin, approbation, ARM, GO/playpause ; aucune nouvelle demande de mot de passe par GO. Expirer la prise de poste et vérifier refus.
7. **Téléphone lecture** : QR lecture/approbation, ShowQ lisible, GO et playpause refusés même armé. Deuxième utilisation et QR >120 s refusés.
8. **Révocation** : révoquer un appareil, tentative avec ancien token refusée ; révoquer tous, tous refusés, backend encore vivant. Reset admin local puis anciennes sessions/appareils refusés.
9. **Désarmement global** : pendant lecture, désarmer ; nouveaux GO/playpause distants refusés, consultation maintenue. Rejouer un nonce déjà accepté et changer son corps : refus.
10. **Câble backup** : débrancher, attendre DOWN ; vérifier HTTP/OSC et contrôle principal indépendants. Envoyer des scènes pendant coupure, rebrancher ; LINK OK sans replay. Nouveau GO seulement. Débrancher l'interface source : aucun changement silencieux de route.
11. **Maintenance** : passer en spectacle et verrouiller, tenter destinations/permissions/agents : refus. Déverrouiller localement + développement, modifier puis reverrouiller. Relire les journaux sans identifiants sensibles.
12. **Désinstallation** : retirer chaque rôle/options, contrôler apps/services/helpers connus absents, anciens composants dans Corbeille, configurations conservées et documentées. Réinstaller puis audit/validate.
