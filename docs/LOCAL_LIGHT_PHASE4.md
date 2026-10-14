# Phase 4 — validation réelle du moteur commun Light

Date : 8 octobre 2026. Branche : feature/local-light.

## Verdict actuel

**NOUVEAU LIGHT NON VALIDÉ — validation réelle encore partielle.**
Ce verdict signifie que tous les scénarios de cette phase ne sont pas encore réalisés. Il ne signifie pas que les essais déjà réalisés ont échoué. Ne pas supprimer LightRuntime ni light_timing.py.

## Scénarios effectivement réalisés

| Scénario | Résultat / preuve |
|---|---|
| Démarrage launcher_light.py avec Live ouvert | LOCAL_LIGHT, SHOW CASSIS (chemin confirmé par Live), 36 scènes dans le Set. Transport arrêté. |
| Absence de commandes automatiques | Relance instrumentée hors dépôt : seules lectures OSC et inscriptions playing_slot_index, aucun fire, stop ou set de sélection au démarrage. |
| PREV/NEXT/GOTO locaux | HTTP 200 ; préparation uniquement. Scène courante et lecture inchangées. GOTO 6 → index 5 ; PREV → index 4 ; NEXT → index 5. |
| GO local | Scène 6 réellement lancée, current_scene=5 ; suivante index 6 préparée. |
| GO anti-doublon | Même request_id envoyé deux fois : un seul /live/scene/fire_as_selected [5] dans la trace OSC. |
| STOP local | Premier essai : arrêt réel mais réponse trop précoce encore playing. Correctif Light, puis arrêt confirmé HTTP 200 et timing courant null. |
| Plusieurs durées réelles | Scène 6 : 74 s ; suivante scène 7 : 375 s. Essai iPhone : scène 32 : 709 s ; préparée 33 : 244 s. Valeurs identiques aux durées déclarées dans les noms du Set .als lu sans modification. |
| Progression | Six snapshots scène 6 : 0.00, 1.01, 2.01, 3.02, 4.02, 5.03 s ; restant correspondant décroissant ; aucune alternance valeur/null sur ces échantillons. |
| iPhone réel HTTPS | L’utilisateur confirme ouverture puis fonctionnement des commandes PREV/NEXT/GO/STOP ; requêtes externes observées sur le serveur. |
| Désarmement | Refus réel sur l’iPhone : télécommandes désarmées. Réarmement local pour le test. Désarmement après redémarrage conforme au comportement existant. |
| HTTPS et commande non autorisée | Contrôle avec CA locale (validation certificat active) : /status 200 ; /action sans signature 403 Appareil inconnu ou révoqué. |
| Interface | Ancien shell FULL injecté découvert puis supprimé uniquement en profil Light. Capture : /private/tmp/cl-phase4-light.png. |

## Scénarios non encore validés en réel dans cette phase

- Lancement manuel d’une scène par le triangle dans Live : manipulation demandée à l’utilisateur, pas de lancement confirmé à ce stade. Les tentatives par automatisation native n’ont pas lancé la scène ; cela ne prouve pas un défaut du moteur.
- Changement de Set et refus effectif de l’ancienne génération sur le nouveau Set.
- Fermeture/réouverture réelle de Live, puis GO après reconnexion.
- Nouveau pairing, approbation et révocation sur l’iPhone réel. La connexion existante a été utilisée ; tests automatiques de pairing/approbation/armement/révocation passent.
- Fluidité visuelle prolongée du compteur et comportement visuel durant la perte de Live.
- Mesure des durées de clips indépendante des durées déclarées : les valeurs ci-dessus sont comparées aux noms des scènes, pas certifiées comme mesure de la longueur sonore.

Les validations réelles des phases antérieures et les fixtures ne remplacent pas ces scénarios sur le nouveau moteur commun.

## Services et ports réellement relevés

Processus de développement instrumenté : Python PID 86887 au moment du relevé.
- TCP 5050, toutes interfaces : interface web et remote HTTP existant.
- TCP 8443, toutes interfaces : HTTPS distant existant.
- UDP 127.0.0.1:11001 : réponses AbletonOSC.
- UDP éphémère 58006 : socket d’émission AbletonOSC (destination loopback).

Threads Python observés : CL Light OSC, CL Light Ableton, CL Light Web, CL Remote TLS ; bootstrap_live_set transitoire ; process_request_thread pour HTTP. Threads macOS/WebKit normaux également présents : NSEventThread, JavaScriptCore, WebCore Scrolling, CVDisplayLink, files de travail natives.

Instances relevées : hot_backup=None, scene_backup_udp=None, backup_scene_follow=None, m4l_client=None, CONSOLE_LIBRARY_STORE=None.
Aucun thread/listener Light de consoles, RTP, LTC/MTC, backup, Arrangement ou découverte Paradis Latin relevé. Les services de profils interdits ne sont pas démarrés dans ce chemin. Le code et certains imports FULL existent toujours : absence de démarrage ne signifie pas absence de modules importés. Les pistes MIDI/LTC/MTC déjà dans le Set Live n’ont pas été modifiées ; leurs propres clips ne sont pas des services lancés par Light.

## Corrections ciblées

1. app.py : garde de profil dans decorate_remote_page_html ; FULL conserve son shell, Light conserve sa propre interface. Suppression du polling visuel FULL supplémentaire induit par le shell.
2. common_light_runtime.py : STOP attend une confirmation OSC bornée à 850 ms (requêtes 200 ms, intervalle 25 ms), vérifie la génération pendant l’attente et ne déclare jamais un succès sans réponse arrêté. Aucun changement du chemin STOP FULL.
3. tests/test_common_light_runtime.py : rendu sans shell FULL, STOP réponse retardée, refus sans confirmation et refus après changement de génération.
4. tests/js/render_remote_fixture.py : fixture AST isolée fournit explicitement capacités FULL, sans importer le serveur réel.
5. Ce rapport.

Sauvegardes préalables : /private/tmp/CL_LIGHT_COMMON_ENGINE_PHASE4_20261008_125403/.

## Ancien / nouveau moteur

Contrats GO/navigation/STOP/génération couverts par les tests de comparaison existants, conservés. Nouveau moteur partage suivi Ableton, GO et timing FULL ; remote sécurisé restauré ; durée préparée disponible. Aucun ancien fichier LightRuntime/light_timing modifié. Pas de comparaison simultanée des deux runtimes réels : ils utilisent le même port OSC. Ne pas conclure à une équivalence réelle complète tant que les scénarios restants ne sont pas terminés.

## Validations finales

- Tests ciblés Light/GO/timing/packaging/common runtime : 117 réussis.
- Python complet : 1345 réussis, 1 ignoré, 122 sous-tests réussis, 1 échec natif préexistant test_simulator_dashboard_ownership[test_simulator_dashboard_control.m]. Exception CLMemoryDefaults stringForKey: ; fichiers natifs concernés inchangés, hors sujet et explicitement autorisés à rester isolés.
- JS : 27/27 suites réussies sur la passe plus les deux suites FULL relancées après adaptation de fixture (105 cas visuels chacune).
- Syntaxe Python et JS : OK.
- git diff --check : OK.
- git status --short inspecté ; modifications antérieures et fichiers non suivis conservés, aucun staging.

Artefacts de preuve hors dépôt : cl-phase4-actions.json, cl-phase4-osc.jsonl, cl-phase4-profile.json, cl-phase4-process-sample.txt, cl-phase4-profile-launcher.log, cl-phase4-python-complete.log dans /private/tmp/.
Aucun commit, push, build Release ou installation. FULL non installé/remplacé. Serveur Light de développement conservé pour poursuivre les essais ; Live arrêté au dernier relevé et télécommandes réarmées pour cet essai.
