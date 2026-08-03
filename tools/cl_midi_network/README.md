# CL MIDI Network Tools

Trois outils natifs macOS fondés sur CoreMIDI :

- `CLMIDINetworkGuardian` active la session RTP-MIDI et reconnecte un correspondant Bonjour.
- `CLMIDINetworkDashboard` est un panneau technique autonome : état et activation de la session RTP, politique d'accès, port UDP, connexions actives, inventaire CoreMIDI, correspondants Bonjour et test d'aller-retour MIDI réel.
- `connect_rtp_peer.applescript` connecte explicitement un correspondant Bonjour choisi, sans cible codee en dur et sans deconnexion globale.
- `CLYamahaConsoleSimulator` reçoit les Program Change de la session RTP et les renvoie après un délai configurable, comme confirmation simulée d'une Yamaha CL/QL.
  Il ignore toutes les copies réfléchies de ses propres confirmations, regroupe
  les doublons en attente et coupe temporairement l'écho si une rafale anormale
  est détectée, afin qu'une boucle RTP ne puisse pas perturber l'audio.
- `CLMIDIRoundTripTester` envoie une scène témoin et mesure sa confirmation aller-retour.
  Après le premier retour, il observe encore le flux pendant 500 ms. Plus de quatre
  confirmations identiques ou plus de seize Program Change pendant cette fenêtre
  sont classés comme une boucle MIDI. L'Assistant affiche alors la consigne sûre :
  dans Ableton, désactiver **Piste** sur l'entrée RTP, conserver **Piste** sur la
  sortie RTP, laisser les routages actifs à **Aucun** et n'établir qu'une paire RTP.
- `reconnect_legacy_rtp.applescript` reconnecte explicitement une ancienne
  session Apple MIDI visible dans Configuration Audio et MIDI.

## Compilation

```sh
./build.sh
```

## Gardien

Sur le Mac contrôleur :

```sh
./build/CLMIDINetworkGuardian --peer-name "MB Pro"
```

Une adresse fixe peut être utilisée comme solution de secours :

```sh
./build/CLMIDINetworkGuardian --peer-name "MB Pro" --peer-host 192.168.1.22 --peer-port 5004
```

Sur les anciennes configurations RTP-MIDI encore gérées par le pilote
`com.apple.AppleMIDIRTPDriver`, l'API moderne `MIDINetworkSession` peut ne pas
retrouver la session pourtant visible dans Configuration Audio et MIDI. Dans ce
cas, le gardien refuse de déclarer la reconnexion réussie. Il ne modifie pas le
fichier de préférences historique et n'invente pas une seconde session.

Lorsque l'ancien pilote est utilisé, la solution de secours validée pilote la
fenêtre système existante sans modifier ses préférences :

```sh
osascript reconnect_legacy_rtp.applescript "MacBook Pro de Mb" "MB Pro"
```

Le premier argument est le nom du correspondant dans le répertoire et le
second son nom réseau une fois connecté. Le script ne déconnecte jamais une
autre session active. Il nécessite que Configuration Audio et MIDI soit
autorisée dans les réglages d'Accessibilité de macOS.

## Simulateur Yamaha

Sur le second Mac :

```sh
./build/CLYamahaConsoleSimulator --label QL1 --delay-ms 80
```

Il écoute la source de la session RTP par défaut et renvoie chaque Program Change sur sa destination RTP. Les numéros bruts MIDI (0–127) et les numéros de scène corrigés (1–128) sont journalisés.

## Test aller-retour

Sur le Mac contrôleur, lorsque le simulateur tourne sur le second Mac :

```sh
./build/CLMIDIRoundTripTester --endpoint "Session RTP 1" --program 42 --timeout 5
```

Le test réussit uniquement si la scène reçue en retour correspond exactement à
la scène envoyée. Il affiche aussi la latence mesurée.

## Assistant réseau autonome

`CL MIDI Network Assistant` s'ouvre en **Vue Assistant** : choisir l'autre Mac,
choisir CL5 ou QL1, puis envoyer une scène témoin et vérifier son retour. Le
bouton **Diagnostic détaillé** affiche séparément les informations techniques.

**Configurer le simulateur distant** est réservé au diagnostic. L'Assistant
doit d'abord vérifier que `CL MIDI RTP Agent` répond, que le simulateur est
installé et s'il est réellement actif. Ne jamais le démarrer avec une vraie
console en exploitation.

`CL MIDI Network Assistant` conserve une écoute passive des retours CL5/QL1 afin
de publier leurs derniers numéros de Program Change pour CL Audio Show Control.
Cette écoute n'émet aucun message MIDI et ne peut donc pas créer de boucle. Le
reste du panneau sert à configurer, inspecter et tester le transport RTP-MIDI.
L'activation de la session RTP et sa politique d'accès restent gérées par la
fenêtre **Réglages de réseau MIDI** de macOS. L'Assistant n'affiche plus l'état
ambigu de la session CoreMIDI par défaut : il s'appuie sur les ports réellement
visibles, les correspondants détectés et le test aller-retour.

Ces outils ne s'installent pas encore au démarrage. Le simulateur et le test ne
modifient pas Configuration Audio et MIDI. Le gardien utilise uniquement l'API
CoreMIDI publique et ne modifie aucun fichier de préférences à la main.
