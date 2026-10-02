# État MIDI local validé — 30 septembre 2026

## Statut

État validé en exploitation réelle.

- Ableton : Local
- Backend Show Control connecté
- Retour consoles : `local_dedicated`
- Source retour détectée :
  `Gestionnaire IAC CL MIDI Return Test`
- 1 simulateur CL5
- 1 simulateur QL1
- aucun doublon
- remplacement automatique des simulateurs validé après redémarrage de Show Control
- GO opérateur réel validé

## Chaîne Program Change locale

```text
Show Control / Ableton
  ↓
Gestionnaire IAC Bus 1
  ↓
CL5 simulator / QL1 simulator
  ↓
CL MIDI Return Test
  ↓
Source CoreMIDI :
Gestionnaire IAC CL MIDI Return Test
  ↓
Show Control

## Validation

- /status : connected = true
- console_return_mode = local_dedicated
- console_return_source = Gestionnaire IAC CL MIDI Return Test
- CL5 : retour confirmé, ~73 ms
- QL1 : retour confirmé, ~76 ms
- GO opérateur réel validé
- 1 simulateur CL5 + 1 simulateur QL1, aucun doublon

## Bonjour

Correctif source préparé dans app.py : handler SIGTERM ciblé, sortie via SystemExit, nettoyage du seul enfant dns-sd possédé, 7 tests isolés réussis. Le correctif Bonjour n est pas installé.

## Snapshot

Voir docs/validated-local-midi-2026-09-30/ pour Git, CoreMIDI, processus, status, sauvegardes, hashes, patch Bonjour et tests.

## Tests plus larges

33 tests passent, 1 échoue dans test_server_ownership à cause d une vérification globale sur .kill() dans launcher_control.py. Cet échec ne concerne pas le correctif Bonjour.

## Contraintes

Aucun reset, aucun commit, aucun renommage MIDI/RTP, aucune modification MTC, aucune installation Bonjour.

## Validation production Bonjour

Correctif installé et validé le 30/09/2026.

Cycle testé : fermeture normale de CL Show Control -> aucun processus CL Audio Controller restant -> aucun dns-sd orphelin -> relance -> 2 processus Show Control normaux et 1 seule annonce Bonjour active.

Statut : VALIDÉ EN PRODUCTION.
