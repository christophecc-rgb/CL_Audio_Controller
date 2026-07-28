#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-2.2.0}"
STAMP="$(date +"%Y-%m-%d_%H-%M-%S")"
RELEASE_ROOT="${CL_RELEASE_OUTPUT_ROOT:-$PROJECT_ROOT/Releases}"
RELEASE_DIR="$RELEASE_ROOT/CL_Audio_Controller_${VERSION}_${STAMP}"
BUILD_ROOT="$(mktemp -d "/private/tmp/CL_Audio_Controller_release_${VERSION}_XXXXXX")"
APP_PATH="$BUILD_ROOT/dist/CL Audio Controller.app"
KIT_ROOT="$BUILD_ROOT/kit/CL Audio Controller $VERSION"
M4L_SOURCE="$PROJECT_ROOT/M4L/Install"
MIDI_DEVICE_SOURCE="$PROJECT_ROOT/M4L/Devices/CL MIDI Console Monitor"
MIDI_TOOLS_SOURCE="$PROJECT_ROOT/tools/cl_midi_network"
ABLETONOSC_ROOT="$(cd "$PROJECT_ROOT/../AbletonOSC" 2>/dev/null && pwd || true)"
PACKAGING_SOURCE="$PROJECT_ROOT/packaging"
DMG_NAME="CL_Audio_Controller_${VERSION}.dmg"
ZIP_NAME="CL_Audio_Controller_${VERSION}_Kit_Complet_macOS.zip"
M4L_ZIP_NAME="CL_Audio_Controller_${VERSION}_Max_for_Live.zip"

cleanup() {
  rm -rf "$BUILD_ROOT"
}
trap cleanup EXIT

if [[ -e "$RELEASE_DIR" ]]; then
  echo "Refus d'écraser une distribution existante : $RELEASE_DIR" >&2
  exit 1
fi

if [[ ! -d "$ABLETONOSC_ROOT/.git" ]]; then
  echo "Dépôt AbletonOSC voisin introuvable : $PROJECT_ROOT/../AbletonOSC" >&2
  exit 1
fi
if [[ ! -f "$ABLETONOSC_ROOT/abletonosc/song.py" ]]; then
  echo "AbletonOSC incomplet : abletonosc/song.py est absent." >&2
  exit 1
fi
if ! grep -Eq 'for prop in \[.*"file_path".*"name".*\]' \
  "$ABLETONOSC_ROOT/abletonosc/song.py"; then
  echo "Routes AbletonOSC file_path/name non détectées dans song.py." >&2
  exit 1
fi
if ! grep -q '"/live/song/get/selected_scene"' \
  "$ABLETONOSC_ROOT/abletonosc/song.py"; then
  echo "Route AbletonOSC requise absente : /live/song/get/selected_scene" >&2
  exit 1
fi

mkdir -p "$RELEASE_DIR"
cd "$PROJECT_ROOT"

echo "========== BUILD $VERSION =========="
python3 -m PyInstaller \
  --noconfirm \
  --workpath "$BUILD_ROOT/build" \
  --distpath "$BUILD_ROOT/dist" \
  "CL Audio Controller.spec"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Bundle introuvable après construction : $APP_PATH" >&2
  exit 1
fi

if [[ ! -d "$M4L_SOURCE" ]]; then
  echo "Dossier Max for Live introuvable : $M4L_SOURCE" >&2
  exit 1
fi
if [[ ! -f "$MIDI_DEVICE_SOURCE/CL MIDI Console Monitor.amxd" ]]; then
  echo "CL MIDI Console Monitor introuvable : $MIDI_DEVICE_SOURCE" >&2
  exit 1
fi

echo
echo "========== KIT D'INSTALLATION =========="
mkdir -p \
  "$KIT_ROOT/AbletonOSC CL/AbletonOSC" \
  "$KIT_ROOT/Documentation"

ditto "$APP_PATH" "$KIT_ROOT/CL Audio Controller.app"
ditto "$M4L_SOURCE" "$KIT_ROOT/Max for Live à installer"
ditto "$MIDI_DEVICE_SOURCE" "$KIT_ROOT/Max for Live à installer/CL MIDI Console Monitor"

"$MIDI_TOOLS_SOURCE/build.sh" "$BUILD_ROOT/midi-tools"
mkdir -p \
  "$KIT_ROOT/CL MIDI Network Tools" \
  "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/MacOS" \
  "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/Resources/Network Tools"
for tool in CLMIDINetworkGuardian CLMIDIRoundTripTester CLYamahaConsoleSimulator CLMIDINetworkDashboard; do
  ditto "$BUILD_ROOT/midi-tools/$tool" "$KIT_ROOT/CL MIDI Network Tools/$tool"
  ditto "$BUILD_ROOT/midi-tools/$tool" "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/Resources/Network Tools/$tool"
done
ditto "$MIDI_TOOLS_SOURCE/reconnect_legacy_rtp.applescript" "$KIT_ROOT/CL MIDI Network Tools/reconnect_legacy_rtp.applescript"
ditto "$MIDI_TOOLS_SOURCE/reconnect_legacy_rtp.applescript" "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/Resources/Network Tools/reconnect_legacy_rtp.applescript"
ditto "$MIDI_TOOLS_SOURCE/connect_rtp_peer.applescript" "$KIT_ROOT/CL MIDI Network Tools/connect_rtp_peer.applescript"
ditto "$MIDI_TOOLS_SOURCE/connect_rtp_peer.applescript" "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/Resources/Network Tools/connect_rtp_peer.applescript"
ditto "$MIDI_TOOLS_SOURCE/list_rtp_peers.applescript" "$KIT_ROOT/CL MIDI Network Tools/list_rtp_peers.applescript"
ditto "$MIDI_TOOLS_SOURCE/list_rtp_peers.applescript" "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/Resources/Network Tools/list_rtp_peers.applescript"
ditto "$MIDI_TOOLS_SOURCE/open_rtp_settings.applescript" "$KIT_ROOT/CL MIDI Network Tools/open_rtp_settings.applescript"
ditto "$MIDI_TOOLS_SOURCE/open_rtp_settings.applescript" "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/Resources/Network Tools/open_rtp_settings.applescript"
ditto "$BUILD_ROOT/midi-tools/CLMIDINetworkDashboard" "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/MacOS/CL MIDI Network Assistant"
ditto "$PACKAGING_SOURCE/CL_MIDI_Network_Assistant.sh" "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/Resources/LegacyAssistant.sh"
ditto "$PROJECT_ROOT/assets/CL_MIDI_Network_Assistant.icns" "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/Resources/CL_MIDI_Network_Assistant.icns"
ditto "$PROJECT_ROOT/M4L/Devices/CL MIDI Console Monitor/paradis_latin_logo.jpg" "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/Resources/paradis_latin_logo.jpg"
chmod +x "$KIT_ROOT/CL MIDI Network Tools"/CLMIDI* "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/MacOS/CL MIDI Network Assistant" "$KIT_ROOT/CL MIDI Network Assistant.app/Contents/Resources/LegacyAssistant.sh"
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
codesign --force --deep --sign - "$KIT_ROOT/CL MIDI Network Assistant.app"

# git archive n'inclut ni .git, ni caches, ni journaux, ni fichiers locaux.
git -C "$ABLETONOSC_ROOT" archive --format=tar HEAD |
  tar -xf - -C "$KIT_ROOT/AbletonOSC CL/AbletonOSC"

cp "$PACKAGING_SOURCE/Installer_CL_Audio_Controller.command" "$KIT_ROOT/"
cp "$PACKAGING_SOURCE/Verifier_SHA256.command" "$KIT_ROOT/"
cp "$PACKAGING_SOURCE/INSTALLATION_NOUVEAU_MAC.txt" "$KIT_ROOT/LISEZ_MOI_INSTALLATION.txt"
cp "$PROJECT_ROOT/README.md" "$KIT_ROOT/Documentation/README.md"
cp "$PROJECT_ROOT/BUILD_ENVIRONMENT.md" "$KIT_ROOT/Documentation/BUILD_ENVIRONMENT.md"
cp "$PROJECT_ROOT/THIRD_PARTY_LICENSES.md" "$KIT_ROOT/Documentation/THIRD_PARTY_LICENSES.md"
cp "$PROJECT_ROOT/LICENSE" "$KIT_ROOT/Documentation/LICENSE"
chmod +x \
  "$KIT_ROOT/Installer_CL_Audio_Controller.command" \
  "$KIT_ROOT/Verifier_SHA256.command"

cat > "$KIT_ROOT/VERSIONS.txt" <<EOF
CL Audio Controller
- version : $VERSION
- commit : $(git rev-parse HEAD)

AbletonOSC CL
- version/tag : $(git -C "$ABLETONOSC_ROOT" describe --tags --always)
- commit : $(git -C "$ABLETONOSC_ROOT" rev-parse HEAD)
- compatibilité documentée : Ableton Live 11 et 12

Max for Live
- source : M4L/Install du commit CL Audio Controller ci-dessus
EOF

(
  cd "$KIT_ROOT"
  shasum -a 256 \
    "CL Audio Controller.app/Contents/MacOS/CL Audio Controller" \
    "AbletonOSC CL/AbletonOSC/abletonosc/song.py" \
    "Max for Live à installer/XFADER OSC BRIDGE v8.amxd" \
    "Max for Live à installer/LTC Display v2.0 Remote Config.amxd" \
    "Max for Live à installer/Paradis Latin AutoScene.amxd" \
    "Max for Live à installer/Paradis Latin AutoScene - Live 10.amxd" \
    "Max for Live à installer/Paradis Latin AutoScene - Live 10.maxpat" \
    "Max for Live à installer/CL MIDI Console Monitor/CL MIDI Console Monitor.amxd" \
    "CL MIDI Network Tools/CLMIDIRoundTripTester" \
    > CONTENU_SHA256.txt
)

echo
echo "========== DMG =========="
hdiutil create \
  -volname "CL Audio Controller $VERSION" \
  -srcfolder "$KIT_ROOT" \
  -format UDZO \
  "$RELEASE_DIR/$DMG_NAME"

echo
echo "========== ZIP COMPLET =========="
ditto -c -k --sequesterRsrc --keepParent \
  "$KIT_ROOT" \
  "$RELEASE_DIR/$ZIP_NAME"

echo
echo "========== ZIP MAX FOR LIVE =========="
ditto -c -k --sequesterRsrc --keepParent \
  "$KIT_ROOT/Max for Live à installer" \
  "$RELEASE_DIR/$M4L_ZIP_NAME"

echo
echo "========== SHA-256 =========="
(
  cd "$RELEASE_DIR"
  shasum -a 256 "$DMG_NAME" "$ZIP_NAME" "$M4L_ZIP_NAME" > SHA256SUMS.txt
)

cat > "$RELEASE_DIR/BUILD_INFO.txt" <<EOF
CL Audio Controller $VERSION
Git commit: $(git rev-parse HEAD)
Built at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Build workspace: $BUILD_ROOT
Architecture: $(uname -m)
AbletonOSC commit: $(git -C "$ABLETONOSC_ROOT" rev-parse HEAD)
Contenu: application autonome + AbletonOSC CL + Max for Live + CL MIDI Console + documentation
Python requis sur le Mac cible: non
EOF

echo
echo "✅ Distribution créée sans remplacer les précédentes :"
echo "$RELEASE_DIR"
ls -lh "$RELEASE_DIR"
echo
cat "$RELEASE_DIR/SHA256SUMS.txt"
