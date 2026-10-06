# Mesure du suivi de scène Hot Backup — 6 octobre 2026

Deux lancements OSC directs vers le Live principal local, sans passer par les commandes de la télécommande CL. Chaque essai dure six secondes, puis la lecture est arrêtée. Le backup est le Mac distant 192.168.1.138. Des abonnements temporaires à ses pistes en lecture sont retirés à la fin.

Les horodatages proviennent d'une seule capture sur le Mac principal : aucune synchronisation des horloges entre machines n'est nécessaire.

| Intervalle observé | Essai 1 | Essai 2 |
| --- | ---: | ---: |
| Commande initiale → retour de piste en lecture du principal | 67,23 ms | 119,90 ms |
| Événement de scène du principal reçu → commande envoyée au backup | 0,93 ms | 1,80 ms |
| Commande au backup → retour de piste en lecture du backup | 207,13 ms | 179,44 ms |
| Retour de piste du principal → retour de piste du backup | 209,16 ms | 183,38 ms |

Le relais de Show Control est rapide sur ces deux essais. La majeure partie de l'écart observé intervient après l'envoi au backup, dans le réseau, le traitement par Live/AbletonOSC et le retour d'état. La répartition exacte entre ces étapes n'est pas mesurée.

Le script AbletonOSC installé sur le principal documente un traitement des commandes dans `manager.tick()` une fois par cycle de 100 ms, via `schedule_message(1, self.tick)`. C'est une piste pour comprendre le délai ; la cadence réelle du script distant n'a pas été vérifiée lors de cette mesure.

Ces valeurs mesurent l'arrivée des notifications de lecture, pas les départs audio. Elles ne prouvent donc pas un décalage audio exact de 183 à 209 ms. Une capture audio commune aux deux sorties serait nécessaire pour établir celui-ci.

Aucun réglage de quantification ni code de production n'a été modifié pour ces essais. Deux essais seulement : ces résultats ne constituent pas une distribution statistique des délais.

## Essai réversible du timer natif sur le backup

La présence et la signature de `Live.Base.Timer(callback, interval, repeat, start)` ont été vérifiées directement dans Live distant. Un timer expérimental de 20 ms a été activé temporairement dans AbletonOSC sur le backup uniquement. Le polling habituel est resté actif en secours ; le callback vérifie qu'il s'exécute sur le même thread Live et s'arrête automatiquement après 90 secondes ou sur erreur. Aucun script LioBox n'a été modifié.

24 requêtes OSC dédiées sans lancement de lecture ont été mesurées dans chaque mode, avec réception sur un port de test indépendant.

| Aller-retour réseau + traitement OSC + réponse | Habituel | Timer 20 ms |
| --- | ---: | ---: |
| Médiane | 54.75 ms | 32.56 ms |
| Moyenne | 72.93 ms | 48.13 ms |
| Minimum | 18.75 ms | 9.37 ms |
| Maximum | 192.67 ms | 140.71 ms |

Le gain médian est d'environ 22 ms sur cet échantillon. Ce test porte sur la réponse OSC, pas sur un lancement de scène ni sur l'audio. Les modes ont été testés successivement ; la variabilité du réseau empêche d'attribuer précisément tout le gain au timer. Une comparaison des départs de lecture reste nécessaire avant intégration.

Le timer a été désactivé, le fichier original a été restauré à l'identique et AbletonOSC rechargé. L'essai ne reste pas actif. Les données brutes locales sont dans `/private/tmp/cl-fast-poll-results.json` et la sauvegarde distante dans `/private/tmp/cl-song-before-timer-test.py`.

## Charge de Live pendant l'essai manuel

Le même lecteur backup (PID 18430) a été observé pendant une lecture maintenue par l'utilisateur : trois séquences rapide / habituel / rapide. Chaque séquence comprend 13 échantillons CPU exploitables de `top` (le premier échantillon est exclu), après deux secondes de stabilisation.

| Mode | CPU moyen du processus Live | CPU médian |
| --- | ---: | ---: |
| rapide_1 | 64.43 % | 67.70 % |
| habituel | 64.49 % | 68.00 % |
| rapide_2 | 64.68 % | 68.30 % |

La moyenne des deux séquences rapides est de 64,56 %, contre 64,49 % pour le fonctionnement habituel : écart de 0,07 point, non significatif sur cette courte observation. Le pourcentage est celui du processus macOS, où 100 % représente un cœur CPU ; il ne s'agit pas du compteur de charge audio interne de Live. Ces mesures ne vérifient pas les dépassements de délai audio ni la stabilité en longue exploitation.

Le mode rapide a été réactivé à la fin, avec son expiration automatique de dix minutes. Données brutes : `/private/tmp/cl-live-load-results.json` et fichiers `cl-live-load-*.txt`.
