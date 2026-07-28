#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-1.0.0}"
STAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
OUTPUT_ROOT="${2:-$PROJECT_ROOT/Releases}"
RELEASE_DIR="$OUTPUT_ROOT/CL_MIDI_Console_${VERSION}_${STAMP}"
WORK_DIR="$(mktemp -d "/private/tmp/CL_MIDI_Console_${VERSION}_XXXXXX")"
KIT_ROOT="$WORK_DIR/CL MIDI Console Suite $VERSION"
DEVICE_SOURCE="$PROJECT_ROOT/M4L/Devices/CL MIDI Console Monitor"
TOOLS_SOURCE="$PROJECT_ROOT/tools/cl_midi_network"

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

fail() { echo "ERREUR : $1" >&2; exit 1; }
[[ ! -e "$RELEASE_DIR" ]] || fail "distribution existante : $RELEASE_DIR"

for required in \
  "CL MIDI Console Monitor.amxd" \
  "CL MIDI Console Monitor.maxpat" \
  "CLMidiConsoleDisplay.js" \
  "CLMidiConsoleConfirmation.js" \
  "paradis_latin_logo.jpg"; do
  [[ -f "$DEVICE_SOURCE/$required" ]] || fail "fichier absent : $required"
done

mkdir -p \
  "$KIT_ROOT/Max for Live/CL MIDI Console Monitor" \
  "$KIT_ROOT/Network Tools" \
  "$KIT_ROOT/Documentation" \
  "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/MacOS" \
  "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/Resources/Network Tools" \
  "$RELEASE_DIR"

"$TOOLS_SOURCE/build.sh" "$WORK_DIR/native-tools"
ditto "$DEVICE_SOURCE/CL MIDI Console Monitor.amxd" "$KIT_ROOT/Max for Live/CL MIDI Console Monitor/CL MIDI Console Monitor.amxd"
ditto "$DEVICE_SOURCE/CL MIDI Console Monitor.maxpat" "$KIT_ROOT/Max for Live/CL MIDI Console Monitor/CL MIDI Console Monitor.maxpat"
ditto "$DEVICE_SOURCE/CLMidiConsoleDisplay.js" "$KIT_ROOT/Max for Live/CL MIDI Console Monitor/CLMidiConsoleDisplay.js"
ditto "$DEVICE_SOURCE/CLMidiConsoleConfirmation.js" "$KIT_ROOT/Max for Live/CL MIDI Console Monitor/CLMidiConsoleConfirmation.js"
ditto "$DEVICE_SOURCE/paradis_latin_logo.jpg" "$KIT_ROOT/Max for Live/CL MIDI Console Monitor/paradis_latin_logo.jpg"

for tool in CLMIDINetworkGuardian CLMIDIRoundTripTester CLYamahaConsoleSimulator CLMIDINetworkDashboard; do
  ditto "$WORK_DIR/native-tools/$tool" "$KIT_ROOT/Network Tools/$tool"
  ditto "$WORK_DIR/native-tools/$tool" "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/Resources/Network Tools/$tool"
done
ditto "$TOOLS_SOURCE/reconnect_legacy_rtp.applescript" "$KIT_ROOT/Network Tools/reconnect_legacy_rtp.applescript"
ditto "$TOOLS_SOURCE/reconnect_legacy_rtp.applescript" "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/Resources/Network Tools/reconnect_legacy_rtp.applescript"
ditto "$TOOLS_SOURCE/connect_rtp_peer.applescript" "$KIT_ROOT/Network Tools/connect_rtp_peer.applescript"
ditto "$TOOLS_SOURCE/connect_rtp_peer.applescript" "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/Resources/Network Tools/connect_rtp_peer.applescript"
ditto "$TOOLS_SOURCE/list_rtp_peers.applescript" "$KIT_ROOT/Network Tools/list_rtp_peers.applescript"
ditto "$TOOLS_SOURCE/list_rtp_peers.applescript" "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/Resources/Network Tools/list_rtp_peers.applescript"
ditto "$TOOLS_SOURCE/open_rtp_settings.applescript" "$KIT_ROOT/Network Tools/open_rtp_settings.applescript"
ditto "$TOOLS_SOURCE/open_rtp_settings.applescript" "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/Resources/Network Tools/open_rtp_settings.applescript"
ditto "$TOOLS_SOURCE/README.md" "$KIT_ROOT/Documentation/OUTILS_RESEAU.md"

ditto "$WORK_DIR/native-tools/CLMIDINetworkDashboard" "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/MacOS/CL MIDI Network Assistant"
ditto "$PROJECT_ROOT/packaging/CL_MIDI_Network_Assistant.sh" "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/Resources/LegacyAssistant.sh"
ditto "$PROJECT_ROOT/assets/CL_MIDI_Network_Assistant.icns" "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/Resources/CL_MIDI_Network_Assistant.icns"
ditto "$DEVICE_SOURCE/paradis_latin_logo.jpg" "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/Resources/paradis_latin_logo.jpg"
chmod +x "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/MacOS/CL MIDI Network Assistant" "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/Resources/LegacyAssistant.sh" "$KIT_ROOT/Network Tools"/CLMIDI*

cat > "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>CL MIDI Network Assistant</string>
<key>CFBundleExecutable</key><string>CL MIDI Network Assistant</string>
<key>CFBundleIdentifier</key><string>com.claudio.midi-network-assistant</string>
<key>CFBundleIconFile</key><string>CL_MIDI_Network_Assistant.icns</string>
<key>CFBundleName</key><string>CL MIDI Network Assistant</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>10.15</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>CL MIDI Network Assistant utilise Configuration audio et MIDI et Événements système pour ouvrir et reconnecter la cible RTP sélectionnée.</string>
</dict></plist>
EOF
xattr -cr "$KIT_ROOT/CL MIDI Network Assistant.app"
codesign --force --deep --sign - "$KIT_ROOT/CL MIDI Network Assistant.app"

cp "$PROJECT_ROOT/packaging/Installer_CL_MIDI_Console.command" "$KIT_ROOT/Installer_CL_MIDI_Console.command"
cp "$PROJECT_ROOT/packaging/Desinstaller_CL_MIDI_Console.command" "$KIT_ROOT/Desinstaller_CL_MIDI_Console.command"
chmod +x "$KIT_ROOT"/*.command

cat > "$KIT_ROOT/LISEZ_MOI.txt" <<EOF
CL MIDI CONSOLE SUITE $VERSION
=============================

1. Fermez Ableton Live.
2. Double-cliquez sur Installer_CL_MIDI_Console.command.
3. Relancez Ableton Live.
4. Placez CL MIDI Console Monitor après le périphérique qui produit le Program Change.

Rôles disponibles : CL5, QL1 CC, QL1 PGM, CL5 retour et QL1 retour.
L'application CL MIDI Network Assistant fournit le test aller-retour, le simulateur
Yamaha et l'accès à la reconnexion des anciennes sessions RTP.

Cette version n'est pas encore signée ni notarisée par Apple.
Commit source : $(git -C "$PROJECT_ROOT" rev-parse HEAD)
EOF

(
  cd "$KIT_ROOT"
  find . -type f ! -name SHA256SUMS.txt -print0 | sort -z | xargs -0 shasum -a 256 > SHA256SUMS.txt
)

DMG="$RELEASE_DIR/CL_MIDI_Console_${VERSION}.dmg"
ZIP="$RELEASE_DIR/CL_MIDI_Console_${VERSION}.zip"
hdiutil create -volname "CL MIDI Console $VERSION" -srcfolder "$KIT_ROOT" -format UDZO "$DMG"
ditto -c -k --sequesterRsrc --keepParent "$KIT_ROOT" "$ZIP"
(
  cd "$RELEASE_DIR"
  shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" > SHA256SUMS.txt
)

echo "$RELEASE_DIR"
cat "$RELEASE_DIR/SHA256SUMS.txt"
