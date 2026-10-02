# Découverte des lecteurs Ableton

La liste « Lecteurs Ableton détectés » de Connexion AbletonOSC découvre uniquement
`_cl-ableton._udp.local.`. Elle ne découvre pas les serveurs CL (TCP 5050), les
sessions RTP, SSH ou tous les Macs du LAN. Aucun paquet OSC n'est envoyé par la
découverte. Aucune configuration n'est écrite par son endpoint GET.

## Publication sur chaque Mac lecteur

AbletonOSC est le composant déjà exécuté dans Live sur le lecteur. L'extension
optionnelle `INSTALLER_AbletonOSC/cl_bonjour.py` ajoute la publication à son cycle
de vie, sans modifier `manager.py`, les routes OSC ni les listeners Live. Elle
utilise le binaire système `/usr/bin/dns-sd` via `subprocess.Popen`, sans shell,
ctypes ni thread. Le Python embarqué de Live 12 a échoué avec l'ancien publisher
natif (`module '_ctypes' has no attribute 'c_void_p'`) ; cette dépendance est supprimée.
Le nom lisible dérive du hostname local (limité à 63 octets UTF-8). Le hostname SRV
`.local` est fourni par mDNSResponder ; le port vient du socket réellement ouvert.

Invocation pour un lecteur nommé `iMac-de-Sono-2`, port 11000 :

```sh
/usr/bin/dns-sd -R 'iMac-de-Sono-2 AbletonOSC' _cl-ableton._udp local. 11000 role=ableton protocol=abletonosc version=1
```

La syntaxe a été vérifiée avec l'aide et le manuel du binaire macOS : `-R` annonce
un service sur la machine courante ; `_udp` détermine le transport ; chaque argument
`clé=valeur` fournit un TXT. La commande reste active pour maintenir l'annonce.
Le publisher ne lit ni ne dépend du texte produit par dns-sd. Ses entrées/sorties
sont redirigées vers DEVNULL, sans pipe susceptible de se remplir.

Un seul enfant est créé quand le socket AbletonOSC écoute réellement sur
`0.0.0.0`. Les ticks du scheduler Live vérifient sa survie, sans le relancer s'il
est déjà actif. Une sortie inattendue est récoltée, puis une nouvelle tentative
est faite au tick suivant. Une erreur de démarrage ne bloque pas AbletonOSC.
Un changement de port ou la fermeture du socket retire l'ancienne annonce.

Au disconnect : SIGTERM, `wait` borné à 0,5 s, puis SIGKILL et un second `wait`
borné si nécessaire. Le handle n'est abandonné qu'après récupération effective du
processus. Un échec de nettoyage conserve son propriétaire et empêche un doublon.
La propriété conservée sur le module Manager permet aussi de fermer l'ancien
publisher avant une nouvelle instance/recharge de l'extension, sans modifier
`manager.py`. Les callbacks déjà programmés de l'ancien propriétaire deviennent
inactifs. Un hook `atexit` nettoie aussi lors d'un arrêt normal de Python.

Ce processus n'est ni un LaunchAgent ni un daemon permanent. Un arrêt brutal de
Live (SIGKILL/crash ne laissant pas tourner disconnect ou atexit) peut toutefois
laisser un enfant : aucun mécanisme de surveillance externe n'est ajouté.

### Installation explicite, Live fermé

Copier le dossier `INSTALLER_AbletonOSC` sur le Mac lecteur, puis depuis ce dossier :

```sh
python3 install_bonjour.py
```

Pour une User Library personnalisée :

```sh
python3 install_bonjour.py --target '/chemin/User Library/Remote Scripts/AbletonOSC'
```

Python 3 doit être disponible pour cette installation. L'installeur sauvegarde
`__init__.py` dans `__init__.py.before-cl-bonjour`, copie `cl_bonjour.py`, et remplace
uniquement l'import de Manager par sa sous-classe Bonjour. Les extensions
existantes (notamment les getters en lecture seule) sont conservées. Une version
non reconnue est refusée. Relancer Live avec AbletonOSC comme surface de contrôle.
L'installation n'a pas été exécutée sur les machines de production pendant le développement.

### Mise à jour d'un Mac déjà équipé (sauvegarde existante)

1. Quitter complètement Live.
2. Copier les fichiers mis à jour `install_bonjour.py` et `cl_bonjour.py` ensemble
   dans le dossier d'installation sur le Mac lecteur.
3. Dans Terminal, se placer dans ce dossier, puis exécuter :

```sh
python3 install_bonjour.py --target "$HOME/Music/Ableton/User Library/Remote Scripts/AbletonOSC"
```

L'installeur détecte l'import `BonjourManager` déjà présent : il actualise
`cl_bonjour.py` sans réécrire `__init__.py` ni remplacer ou supprimer
`__init__.py.before-cl-bonjour`. La sauvegarde existante ne provoque donc pas
un échec sur une installation équipée. Ce cas est couvert par un test de mise
à jour d'un ancien publisher. Utiliser le chemin de User Library effectif si personnalisé.
4. Relancer Live avec la surface AbletonOSC active.
5. Sur le Mac de contrôle, lancer :

```sh
/usr/bin/dns-sd -B _cl-ableton._udp local
```

Attendre une ligne Add portant le nom du lecteur. Vérifier le hostname, le port
et les TXT avec le nom d'instance exactement affiché (exemple) :

```sh
/usr/bin/dns-sd -L 'iMac-de-Sono-2 AbletonOSC' _cl-ableton._udp local
```

Vérifier UDP 11000 et les trois TXT, puis sélectionner → Appliquer → Tester dans
Show Control. Déconnecter la surface AbletonOSC : l'annonce doit disparaître
(événement Rmv), sans processus dns-sd du publisher restant. Réactiver la surface
et vérifier une seule annonce. Ctrl-C termine les commandes de diagnostic.

Pour retirer l'extension, fermer Live, restaurer cette sauvegarde dans
`__init__.py`, puis retirer `cl_bonjour.py`. Une réinstallation officielle complète
d'AbletonOSC remplace le dossier : remettre ensuite l'extension Bonjour.

Références de compatibilité :
- [Point d'entrée officiel](https://github.com/ideoforms/AbletonOSC/blob/master/__init__.py)
- [Cycle de vie Manager](https://github.com/ideoforms/AbletonOSC/blob/master/manager.py)
- [API Bonjour Apple](https://developer.apple.com/documentation/dnssd)

## Découverte dans Show Control

`ableton_discovery.py` utilise le `dns-sd` de macOS : browse du service dédié,
résolution SRV/TXT, puis IPv4 sur l'interface de l'annonce. Les opérations sont
bornées et les sous-processus toujours terminés/récoltés. Au plus 32 annonces
par scan, huit résolutions concurrentes. Aucun service supplémentaire n'est lancé.
`launcher_control.py` expose `/api/ableton-discovery`, en lecture seule.

Les snapshots remplacent entièrement les précédents. Cache mémoire 30 s, aucune
persistance sur disque ; le navigateur redemande un snapshot 35 s après la fin
de la requête précédente. Une erreur efface la liste, sans changer la cible.
Un redémarrage de Show Control démarre avec un cache vide. La disparition brutale
d'une machine peut aussi dépendre du TTL du cache mDNS système ; elle n'est pas
une déconnexion Ableton attestée. Aucun ancien lecteur ne sert de cible de repli.

Filtrage : interfaces Ethernet/Wi-Fi `en*`, actives, connues de networksetup, avec
IPv4 utilisable ; interfaces nommées Dante ou Auto-IP ignorées, de même que VPN,
loopback et interfaces inconnues. Adresses 169.254/16, loopback, multicast,
non spécifiées et réservées rejetées. Les IPv4 sont résolues sur l'interface
retenue. Déduplication par hostname (sans distinction de casse) et port, en
regroupant les IPv4/interfaces. Deux ports distincts ne sont pas fusionnés.

Les noms de service et adresses sont affichés avec `textContent`, jamais comme HTML.
Le diagnostic avancé expose service, heure, lecteurs, IPv4, interfaces et erreurs.

## Choix de la cible et modes

- **Local** : boucle locale inchangée, liste informative mais sélection désactivée.
- **Distant / manuel** : la sélection remplit le brouillon avec le hostname `.local`.
  Le champ reste éditable. Rien n'est appliqué avant le clic sur **Appliquer**.
- **Paradis Latin** : le code actuel a un profil *serveur CL* Paradis distinct des
  profils Ableton Local/Distant. Il reste intact. Une cible Ableton enregistrée
  `iMac-de-Sono-2.local` ou une ancienne IP est conservée jusqu'au choix explicite.
- **Serveur CL distant** : les réglages Ableton restent verrouillés, comme avant.
  Effectuer la sélection depuis Show Control sur le poste backend ; aucune route
  de configuration distante supplémentaire n'est ajoutée.

« Découvert » signifie que SRV/TXT sont reconnus mais IPv4 non résolue ; la ligne
n'est pas sélectionnable. « Résolu » signifie une IPv4 LAN utilisable, pas une
connexion Live validée. Les ports autres que 11000 sont visibles mais non
sélectionnables pour respecter les ports fixes de l'UI existante.

**Appliquer** conserve l'enregistrement et le comportement serveur existants.
**Tester la connexion** conserve exactement le test OSC existant et teste la cible
appliquée, pas le brouillon. Séquence : sélectionner → Appliquer → Tester.

## Validation maison : deux Macs

1. Mac B : installer l'extension ci-dessus, lancer Live et sa surface AbletonOSC.
2. Mac A : lancer le Show Control mis à jour sur le même LAN. Ne pas lancer les simulateurs.
3. Attendre le scan ; vérifier `MacBook-Pro.local`, son IPv4 LAN et UDP 11000.
4. Vérifier que la cible actuelle n'a pas changé. Passer explicitement en Distant.
5. Sélectionner Mac B : seul le champ change, aucune lecture/scène Live ne démarre.
6. Cliquer Appliquer, puis Tester la connexion ; vérifier le résultat du test existant.
7. Vérifier la télécommande et ShowQ sans lancer de commande de production inutile.
8. Désactiver la surface AbletonOSC sur B : après rafraîchissement/expiration mDNS,
   vérifier la disparition de la liste et la conservation de la cible enregistrée.
9. Réactiver la surface : retour dans la liste, toujours sans bascule automatique.
10. Réduire la fenêtre : vérifier le dropdown, les boutons et l'absence de débordement.

## Validation Paradis Latin

1. Installer l'extension sur `iMac-de-Sono-2`, Live fermé, puis relancer Live.
2. Record Blue : relancer Show Control sur le réseau du théâtre.
3. Vérifier `iMac-de-Sono-2.local`, UDP 11000 et `192.168.1.53` si toujours attribuée.
4. Vérifier l'absence de sélection automatique, y compris si la cible maison était enregistrée.
5. Mode Ableton Distant → sélectionner → Appliquer → Tester la connexion.
6. Vérifier que le profil serveur CL n'a pas changé et que les interfaces Dante /
   adresses 169.254 ne sont pas proposées comme IPv4 utilisables.
7. Retour à la maison : relancer Show Control, vérifier l'apparition du lecteur maison
   et sélectionner explicitement la nouvelle cible.

## Limites et tests

macOS seulement ; multicast mDNS autorisé sur le LAN, pas de découverte inter-VLAN
sans relais Bonjour. Les anciennes installations AbletonOSC non équipées de
l'extension ne sont pas proposées : conserver la saisie manuelle en attendant.
Bonjour n'authentifie pas un lecteur. Le test OSC existant reste indispensable.
Une interface Dante avec un nom générique et une IPv4 privée ne peut pas être
identifiée avec certitude : nommer le service réseau « Dante » sur le poste de
contrôle. La route effective du hostname après application reste celle de macOS
et du transport existant ; cette fonctionnalité ne modifie pas le routage réseau.

Tests automatisés sans LAN : `tests/test_ableton_bonjour_publisher.py`
(processus simulés, démarrage unique, arguments, cleanup, reload et échecs),
`tests/test_ableton_discovery.py`,
`tests/js/test_ableton_discovery.cjs`, ainsi que les régressions profils Ableton et
indépendance réseau. Les tests réels à deux Macs et dans Live restent à effectuer.
