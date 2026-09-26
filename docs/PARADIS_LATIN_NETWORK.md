# Réseau Paradis Latin

Le sélecteur **Serveur CL Audio** propose Local, Paradis Latin et Distant manuel. Il est indépendant du réglage AbletonOSC et enregistré dans le fichier réseau existant (`network-config.json`, section optionnelle `cl_server`). Les anciens fichiers restent lisibles ; leurs profils Ableton restent inchangés.

## Utilisation

- **Local** conserve `127.0.0.1:5050` et les contrôles d’ownership existants.
- **Paradis Latin** reconnaît le nom de la machine (notamment le LocalHostName macOS). Sur Record Blue, il conserve la connexion locale. Ailleurs, il résout `iMac-Record-Blue.local`, teste ses adresses `192.168.3.x`, puis le secours `192.168.3.64`, puis les autres adresses utilisables résolues (dont Wi-Fi). Les adresses `169.254.x.x` sont exclues. Le launcher ouvre la télécommande à l’adresse IP effectivement validée, pour éviter une nouvelle résolution sur Dante.
- **Distant manuel** résout et valide uniquement l’adresse ou le hostname saisi, sans secours Paradis Latin.
- **Appliquer / Rechercher** enregistre le choix et relance la découverte. Un serveur absent peut être enregistré, mais reste affiché non validé. Les vérifications distantes sont rafraîchies par le panneau avec un cache maximal de trois secondes.

La validation utilise `/status` et le validateur existant : service, version de protocole, build, launch_id et server_instance_id. Une réponse HTTP seule ne suffit pas. Les redirections HTTP sont refusées. Ce mécanisme vérifie l’identité applicative existante ; il n’ajoute pas d’authentification cryptographique de machine.

Une connexion distante validée n’est jamais adoptée : aucun fichier d’ownership local n’est utilisé pour la posséder. Démarrage, arrêt, redémarrage et adoption locaux sont refusés lorsque le serveur sélectionné est distant. `valid-unowned` demeure non validé localement et n’est pas adopté automatiquement. Changer de sélection ne démarre ni n’arrête un serveur déjà lancé. Les réglages AbletonOSC s’effectuent sur le poste serveur ; ils sont désactivés sur le panneau connecté à un serveur distant.

## Topologie de référence fournie

| Machine | Rôle | Bonjour | Contrôle / RTP | Dante / Auto-IP | Wi-Fi | Session RTP | Port RTP |
|---|---|---|---|---|---|---|---|
| iMac Record Blue | Serveur CL Audio / Show Control | iMac-Record-Blue.local | 192.168.3.64 | 169.254.198.215 | 192.168.1.54 | iMac Record Blue | À relever |
| iMac Sono 2 | Ableton | iMac-de-Sono-2.local | À relever | 169.254.105.45 | 192.168.1.53 | IMAC MIDI | 5006 |
| Mac mini Monitor | Contrôle / ShowQ | Mac-mini-Monitor.local | 192.168.3.73 | 169.254.118.135 | Non renseignée | Mac mini Monitor | 5004 |
| Mac mini Paradis | Contrôle / ShowQ | Mac-mini-de-macmini-paradis.local | À relever | 169.254.65.59 | Non renseignée | Mac mini de macmini-paradis | 5008 |

Sur Record Blue : en7 = contrôle/RTP, en0 = Dante, en1 = Wi-Fi. Les numéros d’interface ne sont pas imposés par le preset. Aucune adresse manquante n’est déduite des listes ARP ou des annonces RTP. L’hôte Ableton affiché provient uniquement de la configuration publiée par le serveur validé ; le preset ne remplace pas cette configuration par Sono 2.

## Vérifications sur site

1. Sur Record Blue : sélectionner Paradis Latin et confirmer `127.0.0.1:5050`, avec ownership validé.
2. Depuis Monitor puis Paradis : confirmer Record Blue, adresse câblée retenue et identité validée ; ouvrir Session, A/B et Arrangement.
3. Vérifier le secours en cas de résolution Bonjour indisponible, et le refus des adresses Dante.
4. Serveur arrêté ou service étranger sur 5050 : aucune validation ni ouverture de télécommande.
5. Vérifier la cible Ableton réelle, l’OSC aller/retour 11000/11001, et relever l’adresse câblée de Sono 2 ; relever aussi celle de Mac mini Paradis et le port RTP de Record Blue.
6. Vérifier les sessions RTP et les retours consoles existants sans changement : CL5 canal 1, QL1 canal 2. Aucun changement MIDI, Program Change, CLF ou CSV n’est requis.
7. Revenir à Local puis Distant manuel, relancer le launcher et confirmer la persistance du choix ainsi que le fonctionnement de l’ownership.

Le launcher reste sur 5055 ; le backend reste sur 5050. Aucun scan des autres équipements Dante ou de toute la plage réseau n’est réalisé.
