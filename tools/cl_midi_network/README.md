# CL MIDI Network Tools

Trois outils natifs macOS fondés sur CoreMIDI :

- `CLMIDINetworkGuardian` active la session RTP-MIDI et reconnecte un correspondant Bonjour.
- `CLYamahaConsoleSimulator` reçoit les Program Change de la session RTP et les renvoie après un délai configurable, comme confirmation simulée d'une Yamaha CL/QL.
- `CLMIDIRoundTripTester` envoie une scène témoin et mesure sa confirmation aller-retour.
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

Ces outils ne s'installent pas encore au démarrage. Le simulateur et le test ne
modifient pas Configuration Audio et MIDI. Le gardien utilise uniquement l'API
CoreMIDI publique et ne modifie aucun fichier de préférences à la main.
