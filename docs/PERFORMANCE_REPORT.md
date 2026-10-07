# Rapport CL MIDI Performance Monitor

Cliquer **Démarrer la mesure**, effectuer l’essai puis **Arrêter et enregistrer**.
Trois fichiers portant le même nom sont enregistrés sur le Bureau :

- CSV : CPU macOS d’Ableton et des outils CL, mémoire et observation MIDI.
- JSONL : chaque échantillon, deltas des interfaces réseau, télémétrie OSC, backup, LTC et retours consoles disponibles.
- TXT : résumé, moyennes, pics, derniers délais OSC distincts observés (médiane, P95, maximum), timeouts et compteurs du backup, totaux par interface et limites.

## Mesures et limites

Le réseau concerne toutes les applications du Mac. La boucle locale est exclue ; les interfaces virtuelles peuvent compter le même trafic plusieurs fois. Les compteurs OSC sont des charges utiles OSC, pas tous les octets sur le réseau. Les erreurs du pilote ne sont pas une mesure des pertes UDP.

La télémétrie est lue sur le Show Control local, avec deux requêtes HTTP asynchrones par seconde. Si ce service est absent, les mesures locales continuent et le rapport signale l’absence. La fenêtre peut afficher un dernier état : les échantillons précisent la disponibilité réelle.

Les délais sont ceux des réponses OSC observées, pas le décalage audio entre les lecteurs. Les commandes backup abandonnées sont des compteurs logiciels, pas des pertes réseau. Les durées d’état sont des estimations aux points d’échantillonnage. Un changement d’instance invalide les différences de compteurs cumulés. Le nombre de messages MIDI reste une estimation ; les octets sont comptés à partir des paquets CoreMIDI reçus. Les sources MIDI disponibles sont connectées au démarrage de la mesure.

Le CPU distant nécessite le moniteur sur le Mac distant. Le CPU audio interne de Live n’est pas mesuré. Le collecteur ajoute le coût de `ps` et des lectures HTTP : utiliser la même instrumentation pour chaque essai comparatif. Aucun test ne commande Ableton ou modifie le réseau.

Pour comparer : même projet et scène, trois minutes sans suivi backup, trois minutes avec suivi, puis cinq minutes d’usage réel. Une capture de paquets séparée reste nécessaire pour attribuer exactement le trafic à chaque protocole ou établir des pertes réseau. La mesure du décalage audio nécessite un dispositif distinct.

La compilation produit une application universelle Intel / Apple Silicon. Le mode CLI `--self-test-report DOSSIER` vérifie le collecteur et la génération des fichiers sans fenêtre ni commande de lecture.
