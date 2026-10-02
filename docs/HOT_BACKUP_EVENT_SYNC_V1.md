# Hot Backup V1 — événements Show Control, PRIMARY indépendant

Implémentation du 30 septembre 2026. Le périmètre V1 retenu après l'audit est
**commandes explicites de CL Show Control uniquement**. Les actions faites
directement dans Live ou depuis un autre contrôleur ne sont pas reproduites.

## Architecture et garanties du code

```text
Commande opérateur
  → envoi PRIMARY existant
  → copie en mémoire, sans attente
       → file bornée → thread BACKUP → UDP OSC vers BACKUP:11000

Réponses Live → socket existante :11001
  source PRIMARY → traitement / confirmations PRIMARY existants
  autre source   → file de réponses BACKUP (uniquement l'IP configurée)
```

Le code conserve l'objet `ableton_transport`, ses requêtes et ses confirmations.
`send_user_transport()` appelle d'abord le `send()` existant, puis la copie,
et conserve sa valeur de retour. La transaction GO Arrangement conserve ses
branches, ses erreurs et ses délais de confirmation PRIMARY ; seuls des appels
à `copy_to_backup()` sont ajoutés après ses envois réussis.

La frontière `copy_to_backup()` n'effectue ni réseau, ni DNS, ni requête, ni
attente. Elle intercepte toute exception BACKUP. La file `put_nowait` contient
64 éléments au maximum. Son mutex interne ne protège aucune opération réseau.
Le thread BACKUP utilise une socket UDP non bloquante, une IPv4 explicite, sans
résolution DNS, sans retry de commande et sans attente d'accusé de réception.
Les retours BACKUP ne participent jamais au résultat HTTP ou à la confirmation
PRIMARY. Même la configuration utilise le tempo PRIMARY déjà reçu, sans prendre
son verrou de requêtes. L'extension ajoute un coût local d'enqueue borné ; elle
ne promet pas un temps réel dur sous saturation générale de macOS/Python.

Aucun événement n'est déduit du SMPTE ou de l'écart entre lecteurs. Le worker
n'émet périodiquement que trois lectures (nom, tempo, is_playing), une fois par
seconde. Il n'envoie aucune correction de position ou vitesse pendant Play.
Si Show Control s'arrête, aucun Stop n'est émis par ce module.

Les réponses `/live/...` de source étrangère sont exclues des requêtes et de
l'état PRIMARY. Les diagnostics `/cl/...`, notamment MIDI consoles, conservent
leur traitement existant. Les deux Lives n'ouvrent pas deux récepteurs concurrents
sur 11001 ; la séparation par IP est indispensable avec AbletonOSC standard.

## Mode et commandes

- **MTC continu** : mode par défaut au lancement du serveur ; copie BACKUP inactive.
  Le bridge, son autostart, start/stop/restart, son MTC et UDP 20810 sont inchangés.
- **Hot Backup** : opt-in en mémoire pour la session, à réarmer après redémarrage
  du serveur ou changement de Set PRIMARY. Aucun fichier de production modifié.
- Arrangement : Continue, Stop, retour Arrangement et positions en beats sont
  copiés aux points de commande utilisateur. GO locator garde la séquence existante
  Continue puis position. NEXT/PREV Arrangement copient Stop puis position connue.
- Session : GO copie le lancement explicite de scène avec `/live/scene/fire`.
  Aucune sélection de vue/scène n'est ajoutée côté BACKUP. NEXT Session reste un
  choix local d'index ; ce n'est pas une position Arrangement en beats.
- Pause/reprise reproduit la commande existante ; il n'y a pas de locate ajouté
  automatiquement pour corriger une dérive entre les positions de pause.

Une commande de plus de **250 ms** est abandonnée. Aucun ancien GO n'est rejoué
après reconnexion. Un événement perdu ou une erreur OSC nécessite un réarmement
à l'arrêt ; l'état BACKUP l'indique. Les commandes normales ne partent qu'après
le contrôle de disponibilité initial ; Stop est tenté même si BACKUP est indisponible
(sous réserve de la même limite d'âge). PRIMARY n'attend jamais ce contrôle.
Le traitement PRIMARY existant reste autoritaire : si sa validation refuse une
commande avant son envoi, V1 n'invente pas une commande BACKUP de remplacement.

## Activation

Dans le widget MTC existant, ouvrir **Sync**, sélectionner **Hot Backup**, saisir
l'IPv4 du Mac BACKUP, confirmer **EXT désactivé** et **mêmes sets / cartes de tempo**,
puis appliquer à l'arrêt. La cible BACKUP est distincte du profil Local/Distant
existant qui désigne toujours PRIMARY. Les IP de PRIMARY/du serveur sont refusées.
V1 utilise les ports AbletonOSC standard : destination 11000, retours 11001.

Le contrôle initial attend BACKUP arrêté, le même nom de Set et le même tempo
initial (tolérance 0,01 BPM). Le tempo PRIMARY doit avoir été reçu depuis moins
de 5 secondes ; sinon ouvrir la vue Arrangement pour alimenter la télémétrie
existante, puis réessayer. Aucune requête supplémentaire n'est envoyée à PRIMARY
par la configuration Hot Backup.

**ONLINE signifie réponses valides récentes**, pas preuve d'identité des fichiers
audio ni confirmation de chaque commande. Même nom ne garantit pas même contenu.
La vérification de la carte de tempo et d'EXT reste manuelle ; le tempo n'est
comparé qu'au contrôle initial afin de ne pas confondre automation et défaut.
Après 3 secondes sans réponses valides, BACKUP est OFFLINE. Nom différent :
NOT READY. Réponse invalide / erreur socket : ERROR. Une perte d'événement impose
NOT READY et réarmement, même si la connexion revient.

AbletonOSC sur BACKUP doit exposer `/live/song/get/name` ainsi que les autres
adresses testées. Le script installé sur le Mac de développement les expose ;
une autre version distante doit être vérifiée. Un autre client OSC sur BACKUP
peut détourner ses notifications ; garder un seul contrôleur pour les essais.

EXT doit être désactivé **manuellement** sur BACKUP. Ne pas activer une autre
poursuite externe concurrente. Le sélecteur ne commande pas EXT et ne coupe pas
le bridge MTC. Au retour au MTC continu, réactiver EXT manuellement à l'arrêt.

## Validation logicielle

```sh
python3 -m pytest tests/test_hot_backup_sync.py \
  tests/test_arrangement_go_transaction.py tests/test_osc_transport.py \
  tests/test_mtc_bridge_control.py tests/test_ableton_targets.py -q
python3 -m py_compile hot_backup_sync.py app.py osc_transport.py launcher_control.py
```

Résultat : **64 tests réussis, 2 sous-tests réussis**, dont 32 tests Hot Backup.
Couverture : thread BACKUP bloqué, hors ligne, socket en erreur, expiration,
réponses invalides, mauvais nom/tempo initial, réponses mélangées, GO PRIMARY
inchangé, Stop HTTP, NEXT en beats, copies avant les confirmations PRIMARY,
mode inactif, feedback Live passif, et 240 secondes simulées du vrai worker avec
uniquement des lectures OSC. Ces essais ne prouvent pas le timing audio réel.

Le test natif MTC existant a aussi été compilé et exécuté : OK.
La suite `tests/test_passive_scene_listeners.py` comporte deux tests existants
en échec (dont trois sous-tests de sélection), reproduits avec la copie exacte
de `app.py` prise avant cette intervention. Aucun correctif de cette logique
préexistante n'est inclus ici. Le flag de scan reste False et aucun appel à
`show_session_view()` ni nouvelle écriture `selected_scene` n'a été ajouté.

## Build isolé

Le module est importé par `app.py`, déjà présent dans les hidden imports du spec.
Aucun changement du spec ni reconstruction du bridge nécessaire.

```sh
PYINSTALLER_CONFIG_DIR=/tmp/cl-event-sync-build-cache \
  .venv/bin/python -m PyInstaller --noconfirm \
  --distpath /tmp/cl-event-sync-build/dist \
  --workpath /tmp/cl-event-sync-build/work 'CL Audio Controller.spec'
```

Build exécuté et validé : universal2 arm64 / x86_64, signature vérifiée avec
`codesign --verify --deep --strict`, module `hot_backup_sync` présent dans le bundle.
Le build est créé à `/tmp/cl-event-sync-build/dist/CL Show Control.app` ; il ne
remplace pas l'application installée. Ne pas ouvrir ce build en parallèle de
Show Control en exploitation, car l'autostart du bridge existant reste actif.

## Essai sur les deux Macs

1. Hors exploitation, conserver l'application actuelle comme fallback. Charger
   les copies identiques du Set, locators et carte de tempo. Vérifier que le routage
   BACKUP destiné au secours audio n'envoie pas de commandes consoles en double,
   particulièrement avant les essais GO Session. Le code ne modifie aucun routage.
2. BACKUP arrêté : désactiver EXT manuellement, vérifier AbletonOSC sur 11000,
   laisser passer les retours 11001 vers Show Control. Ne pas lancer un autre
   client AbletonOSC concurrent pour les mesures.
3. PRIMARY arrêté et prêt : activer Hot Backup dans le widget ; attendre ONLINE.
   Préparer le locator correspondant à 02:10:00 par la commande Arrangement
   habituelle. Contrôler visuellement les deux positions.
4. GO du locator : vérifier les départs, l'absence de bref départ audible à une
   ancienne position (comportement Continue propre à Live), puis quatre minutes
   sans chasse audible. Mesurer l'écart initial et final. Choisir la tolérance
   acceptable au spectacle ; aucun seuil audio n'est prétendu validé par logiciel.
5. STOP / NEXT / GO, puis locate explicite pendant Play : les deux suivent.
   Play/Stop/Locate directement dans Live ne doivent déclencher aucune copie.
6. Éteindre/débrancher BACKUP, puis GO/STOP/NEXT PRIMARY : mêmes commandes et
   mêmes réponses qu'en MTC continu. BACKUP indique son défaut séparément.
   Reconnecter : pas de vieux GO ; réarmer à l'arrêt et préparer de nouveau.
7. Pendant un morceau, simuler la panne de PRIMARY et basculer l'audio vers
   BACKUP : celui-ci doit continuer. Fermer Show Control pendant un autre essai :
   les deux lecteurs déjà lancés doivent continuer sans dépendance au serveur.
   Si le serveur PRIMARY n'est plus prêt, sa validation de commandes existante
   reste applicable ; arrêter BACKUP localement si la commande Show Control est refusée.
8. Tester mauvaise version OSC, mauvais nom de Set et mauvais tempo initial :
   état BACKUP NOT READY/ERROR, sans changement du fonctionnement PRIMARY.

## Rollback sans reset ni commit

À l'arrêt, sélectionner **MTC continu** et appliquer : les copies sont désactivées,
les événements de l'ancienne session sont invalidés ; aucune commande Stop/Locate
implicite n'est envoyée. Réactiver EXT sur BACKUP et vérifier la chaîne MTC habituelle.
Pour revenir à l'application précédente, fermer le build de test et ouvrir la
copie d'application conservée. Ne pas exécuter de reset Git : le dépôt contient
d'autres modifications à conserver. Les changements de cette intervention sont
limités aux six fichiers ci-dessous ; conserver un diff ciblé pour un retrait
ultérieur du code plutôt que remplacer globalement les fichiers déjà modifiés.

## Fichiers de cette intervention

- `hot_backup_sync.py` : nouveau worker indépendant et diagnostics.
- `app.py` : copies explicites et route de réglage/état.
- `osc_transport.py` : séparation des réponses Live et cache du tempo déjà reçu.
- `launcher_control.py` : réglage discret dans le widget et relais vers le serveur CL.
- `tests/test_hot_backup_sync.py` : tests ciblés.
- `docs/HOT_BACKUP_EVENT_SYNC_V1.md` : cette procédure.

Aucun reset, aucun commit, aucune activation sur les deux Lives depuis ces outils.
