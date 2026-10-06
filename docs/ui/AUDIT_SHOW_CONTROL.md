# Audit et proposition — CL Show Control

La fenêtre actuelle juxtapose un écran d'exploitation et un écran de configuration. Les formulaires occupent la même place une fois les connexions validées ; les explications, états et adresses sont répétés. Réduire seulement les polices aggraverait la lecture.

## Constats

- La carte système, les messages « configuration enregistrée » et « connexion vérifiée », les résumés de synchronisation et les diagnostics présentent plusieurs fois la même information.
- Les trois commandes serveur ont autant de poids que l'ouverture de la télécommande, alors qu'elles servent surtout au démarrage ou à la maintenance.
- L'armement des télécommandes est dans Outils, loin de leur ouverture.
- Le backup affiche en permanence son adresse, ses confirmations, deux résumés et deux explications. L'action importante paraît secondaire.
- Les ports OSC, la destination LTC et les détails du moniteur sont visibles dans la vue courante, sans action fréquente correspondante.
- Les boutons d'armement et de suivi sont petits, sans hiérarchie visuelle claire.

## Organisation proposée

1. Bandeau compact : état général et anomalies prioritaires ; conserver le LTC si utile.
2. Ligne d'exploitation : Ouvrir la télécommande, état Armées/Désarmées et action Désarmer/Armer immédiatement à côté.
3. Colonne gauche : trois cartes compactes CL Show Control / Lecteur principal / Backup. Chaque carte montre la machine active en Bonjour et son état réel. Les formulaires se replient après validation.
4. Backup : badge Suivi actif/inactif et action principale adaptée à l'état. Configuration et confirmations sont dans « Configurer le backup ». Réarmer reste manuel après redémarrage.
5. Colonne droite : deux retours consoles avec titre, numéro, conformité, âge et source réelle/simulateur. Valeurs attendues et données techniques dans les détails. Les défauts restent visibles dans la vue compacte.
6. Outils : ShowQ et Réseau MIDI. Adresses à partager dans un volet, avec disposition symétrique.
7. Services et diagnostic : commandes serveur et MTC, ports, endpoints et journaux. En cas de panne, afficher l'action de récupération directement dans la vue principale.

## Lisibilité

- Boutons principaux : hauteur minimale de 40 px, texte de 14 px. Titres de carte : 14 px ; noms de machines : 16 px ; détails : 12 px.
- Bleu : action principale disponible (ouvrir, armer, activer le suivi).
- Vert : état confirmé (armées, suivi actif, connexion validée), affiché comme badge distinct du bouton.
- Ambre : désarmer ou désactiver ; rouge réservé aux défauts et aux arrêts nécessitant une attention particulière.
- Un libellé accompagne toujours la couleur. Un état inconnu ou ancien ne devient pas vert.
- Aucun masquage des refus, erreurs, retours périmés ou discordances. Le formulaire s'ouvre lorsqu'une intervention est requise.

La maquette utilise des états illustratifs, sans commander les applications. La proposition conserve les protections d'armement et la séparation entre désactivation du suivi et arrêt de lecture.

## Mise en œuvre et vérification

La présentation compacte est installée. Les contrôles existants sont déplacés dans des volets, sans changer leurs routes ni leurs validations. L'affichage principal des consoles met en avant le PC reçu ; attendu/reçu restent visibles en petit, et les scènes, titres attendus, âges, délais et canaux restent dans les détails.

Vérification dans le navigateur : aucun des 22 éléments de contrôle vérifiés ne manque ; les quatre volets de configuration/partage s'ouvrent et conservent leurs champs ; les commandes serveur/MTC restent accessibles ; aucune erreur JavaScript observée. Le suivi backup et l'armement ont été restaurés après installation. Les 50 tests Python ciblés et les deux tests JavaScript connexion/boutons passent.

Les anciens tests `test_console_health.cjs` et `test_console_health_ui.cjs` nécessitent une actualisation : ils attendent notamment le niveau `warning` pour l'attente, alors que le code antérieur à cette réorganisation utilise déjà `neutral`, ainsi que d'anciens libellés. Le second nécessite également Playwright absent de cet environnement. Ils ne sont pas présentés comme réussis ; l'interface a été vérifiée directement avec le navigateur disponible.

## Noms Bonjour dans les fenêtres

Les libellés de Show Control, lecteur principal, sélecteurs et backup privilégient les noms `.local` effectivement découverts. La destination LTC utilise le même affichage. Le champ backup présente et accepte le nom Bonjour ; l'activation le convertit en IPv4 via la découverte existante, en préférant l'adresse déjà active si elle est encore publiée. Un nom non résolu est refusé explicitement. Le transport du backup conserve sa destination IPv4.

Les adresses HTTP de partage Remote/ShowQ privilégient également le nom Bonjour ; les URL HTTPS configurées sont conservées pour respecter l'identité du certificat. Les adresses numériques restent dans le diagnostic et les infobulles. Les fenêtres MIDI utilisent déjà les noms des correspondants/services Bonjour ; les noms de ports MIDI restent ceux publiés par CoreMIDI. Aucun nom n'est inventé pour une IP sans correspondance connue.

Résolution vérifiée : MacChris.local est joignable depuis le Mac distant à 192.168.1.101 ; MacBook-Pro.local est affiché pour le backup 192.168.1.138. Vérification visuelle du champ backup et des URL de partage, ainsi que 13 tests Python et deux tests JavaScript ciblés réussis.
