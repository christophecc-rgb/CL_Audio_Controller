# Audit ciblé CL / Ableton — 13 septembre 2026

## Conclusion

Le rapport ne permet pas d'attribuer le crash aux applications CL. Il montre une erreur mémoire dans Live lors du traitement d'un clic de souris. Les relevés disponibles ne suggèrent pas une saturation audio avant la panne. Un risque nul ne peut pas être garanti : les commandes CL agissent sur Live, AbletonOSC s'exécute dans Live et les devices Max for Live participent à son fonctionnement.

Il s'agit d'une analyse du crash et d'une revue ciblée des chemins d'intégration du dépôt courant, pas d'une certification de toutes les applications CL ou des exécutables installés. Aucun test de lecture, arrêt, modification de Set ou mesure comparative de charge n'a été exécuté sur la machine.

## Preuves du rapport

Archive examinée : Ableton Crash Report 2026-09-13 022329 Live 12.4.5.zip.

- Crash/Live-2026-09-13-022316.ips : Live 12.4.5, Apple M5, 24 Gio de RAM, macOS 26.5.2, exécution native ARM.
- Capture : 13 septembre, 02:23:09 +0200. Exception EXC_BAD_ACCESS / SIGSEGV, KERN_INVALID_ADDRESS à 0x50.
- Thread fautif : MainThread, com.apple.main-thread. Sept premières trames dans Live, puis AppKit `_handleMouseDownEvent`, routage des événements et boucle de l'application.
- Les fonctions internes de Live ne sont pas symboliquées. Cela identifie le contexte du crash, pas sa cause racine, ni le bouton cliqué. Aucun appel CL, AbletonOSC ou Max n'est nommé dans cette pile fautive ; cette absence n'exclut pas un effet indirect ou antérieur.
- Preferences/Log.txt commence à 02:23:28 après le crash : c'est le redémarrage, pas le journal détaillé des actions précédant la panne.
- UsageData/20260911T151032_71810.log correspond au PID 71810 du processus planté. Les heures sont cohérentes avec UTC, par comparaison avec son lancement en heure locale. Dernier relevé : 00:22:44, soit environ 02:22:44 locale.
- Trente derniers relevés : audio_drop_outs = 0 pour chacun ; audio_usage_average entre 2,59 et 4,22 ; maximum audio_usage_peak = 9,48. Ce sont les valeurs de télémétrie audio de Live, pas un pourcentage CPU imputable à CL. Elles ne prouvent pas une lecture continue ni l'absence d'un événement après le dernier relevé.
- Le Set de récupération embarqué contient notamment des références à LTC Display v1.9, MIDI Monitor et CC to Program Change. Il ne constitue pas un inventaire fiable de tous les devices présents en mémoire au crash. La présence des bibliothèques Max dans le processus ne désigne aucun device comme coupable.

## Risques relevés dans le code

| Chemin | Constat | Conséquence possible |
|---|---|---|
| Interface et serveur CL externes | Processus distinct de Live ; échanges OSC | Consommation CPU/RAM sur le même Mac ; une fermeture de l'interface n'implique pas automatiquement un crash de Live |
| Rafraîchissement, app.py:266–280 et background_refresh | Suivi nominal toutes les 0,5 s, rafraîchissement complet toutes les 1 s, boucle de 0,25 s | Charge régulière de contrôle ; les durées des requêtes allongent la cadence réelle |
| scan_playing_scene_from_tracks | Lecture groupée des index de clips et noms de toutes les pistes ; repli séquentiel | Coût croissant avec la taille du Set, et coût supplémentaire si le repli est utilisé |
| osc_transport.py | Requêtes sérialisées, délais d'attente ; envoi direct sans plafond global | Protections utiles contre les requêtes concurrentes, mais pas de limitation commune à toutes les sources de commandes |
| AbletonOSC installé, abletonosc/osc_server.py:148 et manager.py:118 | Vidage synchrone de la socket jusqu'à ce qu'elle soit vide, sans quota de messages ni budget de temps par passage | Une rafale soutenue peut monopoliser le traitement et ralentir Live ; possibilité à corriger, aucune preuve qu'elle ait causé ce crash |
| AbletonOSC, adresse de retour | Destination des notifications mise à jour vers le dernier client | Plusieurs clients directs peuvent perturber les retours d'état ; pas une preuve de crash |
| Transport dans app.py | Commandes stop_playing, déplacement du transport et lancement de scène | Une commande incorrecte ou concurrente peut interrompre le spectacle sans faire planter Live |
| XFADER OSC BRIDGE v8 | udpreceive → clip → sig~ → live.remote~, liaison de paramètre stable | Traitement dans Live, y compris signal de contrôle audio ; coût non nul, non mesuré |
| AutoScene | qmetro 500, actualisation des noms et appel LiveAPI scene.fire | Coût de contrôle ; lancement automatique si armé. Les noms sont relus lors de refresh, pas à chaque tick |

La version du dépôt, notamment ses modifications locales, n'a pas été comparée aux bundles effectivement utilisés au moment du crash. Le script AbletonOSC examiné est celui actuellement installé, sans preuve qu'il était actif pendant toute la session.

## Impact sur l'ordinateur maître

Si les interfaces CL tournent sur le maître, elles partagent processeur, mémoire et ressources graphiques avec Live. Les compilations, exports et tests ajoutent leur propre charge. Si elles tournent sur un autre ordinateur, leur interface est déportée, mais le maître continue de traiter OSC/MIDI, AbletonOSC et ses devices Max for Live.

Le contrôle ne demande pas intrinsèquement de relire une seconde fois tous les fichiers audio. Son coût concerne surtout le pilotage et l'affichage, plus le traitement des devices. Une faible consommation globale ne garantit pas l'absence de pics affectant une échéance audio.

## Validation nécessaire pour quantifier le risque réel

Sur une copie du Set, avec la configuration audio réelle et un scénario identique, comparer : Live seul sans les intégrations CL ; puis AbletonOSC ; puis les devices un par un ; puis une application CL ; puis la configuration complète. Redémarrer Live entre les configurations si nécessaire. Mesurer la charge audio moyenne et de pointe, les décrochages, CPU et mémoire des processus, délais des commandes et trafic OSC. Inclure lancements, transitions, changement de Set et perte/reprise réseau ; terminer par une répétition complète.

Priorités proposées : quota/budget temporel de traitement OSC ; limitation/coalescence des commandes répétitives ; éviter plusieurs pilotes directs concurrents ; conserver les scans complets et les compilations hors exploitation. Ces changements doivent être validés pour ne pas retarder les commandes de spectacle. Aucune modification fonctionnelle réalisée dans cet audit.

Pour la cause exacte, faire symboliquer le rapport par Ableton et chercher une reproduction du clic avec/sans intégrations. Aucun rapport n'a été envoyé à un tiers.

## Références officielles

- [Ableton — Troubleshooting a crash](https://help.ableton.com/hc/en-us/articles/209773265-Troubleshooting-a-crash) : les scripts de contrôle font partie des composants à isoler.
- [Ableton — Monitoring Live's CPU usage](https://help.ableton.com/hc/en-us/articles/209069609-Monitoring-Live-s-CPU-usage-on-your-computer) : distinguer charge audio et CPU global.
- [Ableton — Computer Audio Resources and Strategies](https://www.ableton.com/en/manual/computer-audio-resources-and-strategies/) : traitement par buffers et contraintes de lecture.
