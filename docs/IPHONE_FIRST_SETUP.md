# Première configuration iPhone — CL Show Control

Sur le Mac, ouvrir `http://127.0.0.1:5050/security/panel`, puis **Première configuration iPhone**.
Créer le mot de passe administrateur (12 caractères minimum), puis choisir **Déverrouiller 5 min** ou
**Déverrouiller pour cette session**. Cliquer **Autoriser le mode configuration**, puis **Préparer la connexion sécurisée**.
L’adresse Bonjour est proposée automatiquement ; les réglages détaillés sont dans **Avancé / Diagnostic**.
Aucun chemin de certificat ni outil en ligne de commande n'est nécessaire.

L'application génère une autorité de certification (CA) propre à ce Mac et un certificat serveur signé par cette CA,
puis démarre HTTPS. « HTTPS prêt sur le Mac » signifie qu'une connexion TLS a validé la chaîne, le nom et l'identité du backend.
Cela ne prouve pas encore l'accès depuis le réseau du téléphone.

## Sur l'iPhone

1. Connecter le Mac et l'iPhone au même réseau sans isolation des clients Wi-Fi.
2. Depuis le Mac, afficher le QR du certificat public, puis le scanner dans Safari.
   Le profil public peut aussi être téléchargé sur le Mac et transféré par AirDrop.
3. Installer le profil dans Réglages → Général → VPN et gestion de l'appareil.
   Vérifier les détails du certificat et son empreinte SHA-256 avec celle affichée sur le Mac.
   La récupération initiale par HTTP ne prouve pas l'identité de la CA ; en cas de doute, utiliser AirDrop depuis le Mac connu.
4. Activer la confiance totale pour cette CA dans Réglages → Général → Informations → Réglages des certificats.
   [Instructions Apple](https://support.apple.com/fr-fr/102390).
5. Scanner le QR du test HTTPS et ouvrir la page dans Safari **sans ignorer d'avertissement de certificat**.
   Cliquer **Confirmer la connexion de cet iPhone**. Le Mac affiche « iPhone vérifié » pendant deux minutes.
6. Sur le Mac, cliquer **Ajouter cet iPhone comme télécommande**, le scanner depuis le téléphone puis autoriser la demande sur le Mac.
   Le choix Permanent est proposé explicitement pour un opérateur ; une autorisation temporaire reste possible.
   La progression, la demande et l’appareil autorisé s’affichent automatiquement, sans rechargement. Armer les télécommandes seulement quand le poste est prêt.

Le certificat serveur identifie le Mac ; la CA publique permet à l'iPhone de le vérifier.
Les clés privées du serveur et de la CA restent sur le Mac, dans le dossier privé Security.
Le profil ne contient aucun mot de passe, clé privée ou identifiant de télécommande.
La confiance dans une CA est un choix de sécurité : n'installer que celle du Mac connu et la retirer si elle n'est plus utile.

## Déverrouillage administrateur

Le mode 5 minutes affiche le temps restant. Le mode **pour cette session** exige aussi le mot de passe et
reste uniquement en mémoire tant que le backend tourne. Il est perdu à la fermeture ou au redémarrage,
sans changer le mot de passe enregistré ni armer les télécommandes. **Verrouiller maintenant** invalide
immédiatement les sessions admin. Aucun déverrouillage permanent n’est enregistré sur disque.

## Après redémarrage et changement de réseau

La configuration HTTPS, le mot de passe et les appareils permanents sont conservés dans
`~/Library/Application Support/CL Audio Controller/Security`.
Les appareils temporaires restent soumis à leur durée et à la session serveur ; leur autorisation ne survit pas au redémarrage.
Le serveur redémarre en mode spectacle avec les télécommandes désarmées et l'administration verrouillée.
Un changement d'IP n'impose pas un nouveau certificat si le nom Bonjour du Mac reste le même.
Après un changement de nom Bonjour, choisir le nouveau nom et relancer la configuration : la CA est conservée,
mais un nouveau certificat serveur est signé. Refaire le test iPhone.

Un port occupé, une clé absente ou un certificat invalide apparaît dans les diagnostics et n'empêche pas HTTP 5050 de fonctionner.
Un QR opérateur ne peut pas être généré sans test TLS réussi et confirmation récente depuis le téléphone.
La configuration avancée avec certificat fourni reste disponible : après enregistrement, utiliser **Démarrer / recharger**.
Le certificat fourni doit être reconnu par l'autorité habituelle ; le profil CA proposé concerne uniquement les certificats générés par l'application.

## Kit portable et validation

Le kit doit être reconstruit pour inclure `remote_tls`, les pages du parcours et le runtime Python SSL.
La configuration privée et la CA ne sont pas incluses dans le kit : chaque nouveau Mac crée sa propre CA après une action admin explicite.
La génération utilise `/usr/bin/openssl`, fourni par macOS, sans installation d'OpenSSL ni de module cryptographique supplémentaire.
Les QR utilisent `qrcode`, déjà déclaré dans les dépendances et le packaging.

Depuis le Mac :

```sh
curl -fsS http://127.0.0.1:5050/status
curl -fsS http://127.0.0.1:5050/security/diagnostics
```

Après la configuration, utiliser dans Safari sur l'iPhone l'URL et le QR de test affichés dans l'interface.
Pour un contrôle indépendant depuis le Mac, adapter le nom Bonjour :

```sh
curl --cacert "$HOME/Library/Application Support/CL Audio Controller/Security/https/ca.pem" \
  https://nom-du-mac.local:8443/remote/ready
```

Ne pas utiliser `curl -k` et ne pas contourner un avertissement Safari.
