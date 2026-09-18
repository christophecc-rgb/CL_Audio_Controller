#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-2.2.0}"
CL_PYTHON="${CL_PYTHON:-$PROJECT_ROOT/.venv/bin/python}"
export CL_BUILD_ARCH="${CL_BUILD_ARCH:-universal2}"
STAMP="$(date +"%Y-%m-%d_%H-%M-%S")"
RELEASE_ROOT="${CL_RELEASE_OUTPUT_ROOT:-$PROJECT_ROOT/Releases}"
RELEASE_DIR="$RELEASE_ROOT/CL_Audio_Controller_${VERSION}_${STAMP}"
BUILD_ROOT="$(mktemp -d "/private/tmp/CL_Audio_Controller_release_${VERSION}_XXXXXX")"
APP_PATH="$BUILD_ROOT/dist/CL Show Control.app"
KIT_ROOT="$BUILD_ROOT/kit/CL Audio Controller $VERSION"
M4L_SOURCE="$PROJECT_ROOT/M4L/Install"
MIDI_DEVICE_SOURCE="$PROJECT_ROOT/M4L/Devices/CL MIDI Console Monitor"
MIDI_TOOLS_SOURCE="$PROJECT_ROOT/tools/cl_midi_network"
ABLETONOSC_ROOT="$(cd "$PROJECT_ROOT/../AbletonOSC" 2>/dev/null && pwd || true)"
BUILDER_DIR="$PROJECT_ROOT/../CL_Arrangement_Builder_Live"
PACKAGING_SOURCE="$PROJECT_ROOT/packaging"
DMG_NAME="CL_Audio_Controller_${VERSION}.dmg"
ZIP_NAME="CL_Audio_Controller_${VERSION}_Kit_Complet_macOS.zip"
M4L_ZIP_NAME="CL_Audio_Controller_${VERSION}_Max_for_Live.zip"
SKIP_DMG="${CL_RELEASE_SKIP_DMG:-0}"

cleanup() {
  rm -rf "$BUILD_ROOT"
}
trap cleanup EXIT

# === CL COMPLETE DESKTOP KIT HELPERS ===

sign_universal_binary() {
  local binary="$1"
  local temp_dir
  temp_dir="$(mktemp -d "$BUILD_ROOT/sign-fat.XXXXXX")"

  /usr/bin/lipo "$binary" -thin arm64 -output "$temp_dir/arm64"
  /usr/bin/lipo "$binary" -thin x86_64 -output "$temp_dir/x86_64"

  /usr/bin/codesign --force --sign - "$temp_dir/arm64"
  /usr/bin/codesign --force --sign - "$temp_dir/x86_64"

  /usr/bin/lipo -create \
    "$temp_dir/arm64" \
    "$temp_dir/x86_64" \
    -output "$temp_dir/universal"

  /usr/bin/codesign --force --sign - "$temp_dir/universal"
  /usr/bin/ditto "$temp_dir/universal" "$binary"
  chmod +x "$binary"

  rm -rf "$temp_dir"
  /usr/bin/codesign --verify --strict "$binary"
}

verify_universal() {
  local binary="$1"
  local archs
  archs="$(/usr/bin/lipo -archs "$binary")"

  [[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || {
    echo "Binaire non universel : $binary ($archs)" >&2
    return 1
  }
}

make_native_app() {
  local source_binary="$1"
  local app_path="$2"
  local executable_name="$3"
  local display_name="$4"
  local bundle_id="$5"
  local icon_path="${6:-}"
  local bundled_resource="${7:-}"

  rm -rf "$app_path"
  mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"

  # Le fat binary doit être préparé/signé AVANT son entrée dans le bundle.
  # Une resignature depuis Contents/MacOS fait considérer le binaire comme
  # l'exécutable principal d'un bundle encore non scellé.
  verify_universal "$source_binary"
  sign_universal_binary "$source_binary"

  /usr/bin/ditto "$source_binary" \
    "$app_path/Contents/MacOS/$executable_name"
  chmod +x "$app_path/Contents/MacOS/$executable_name"

  if [[ -n "$icon_path" && -f "$icon_path" ]]; then
    /usr/bin/ditto "$icon_path" \
      "$app_path/Contents/Resources/CL_AUDIO.icns"
  fi
  if [[ -n "$bundled_resource" && -f "$bundled_resource" ]]; then
    /usr/bin/ditto "$bundled_resource" "$app_path/Contents/Resources/$(basename "$bundled_resource")"
  fi

  cat > "$app_path/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>$display_name</string>
<key>CFBundleExecutable</key><string>$executable_name</string>
<key>CFBundleIdentifier</key><string>$bundle_id</string>
<key>CFBundleName</key><string>$display_name</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>10.15</string>
<key>NSHighResolutionCapable</key><true/>
EOF

  if [[ -n "$icon_path" && -f "$icon_path" ]]; then
    echo '<key>CFBundleIconFile</key><string>CL_AUDIO.icns</string>' \
      >> "$app_path/Contents/Info.plist"
  fi

  cat >> "$app_path/Contents/Info.plist" <<EOF
</dict></plist>
EOF

  /usr/bin/plutil -lint "$app_path/Contents/Info.plist" >/dev/null
  /usr/bin/xattr -cr "$app_path"
  /usr/bin/codesign --force --sign - "$app_path"
  /usr/bin/codesign --verify --deep --strict "$app_path"
}

if [[ -e "$RELEASE_DIR" ]]; then
  echo "Refus d'écraser une distribution existante : $RELEASE_DIR" >&2
  exit 1
fi

if [[ ! -d "$ABLETONOSC_ROOT/.git" ]]; then
  echo "Dépôt AbletonOSC voisin introuvable : $PROJECT_ROOT/../AbletonOSC" >&2
  exit 1
fi

if [[ ! -d "$BUILDER_DIR/.git" ]]; then
  echo "Dépôt CL_Arrangement_Builder_Live voisin introuvable : $BUILDER_DIR" >&2
  exit 1
fi

if [[ ! -f "$BUILDER_DIR/Arrangement Builder Live.spec" ]]; then
  echo "Spec Arrangement Builder introuvable : $BUILDER_DIR/Arrangement Builder Live.spec" >&2
  exit 1
fi

if [[ ! -d "$BUILDER_DIR/RemoteScript" ]]; then
  echo "Remote Script Arrangement Builder introuvable : $BUILDER_DIR/RemoteScript" >&2
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
"$CL_PYTHON" -c "import pypdf, PyInstaller"
"$CL_PYTHON" "$PROJECT_ROOT/scripts/generate_app_icon_variants.py"
"$CL_PYTHON" -m PyInstaller \
  --noconfirm \
  --workpath "$BUILD_ROOT/build" \
  --distpath "$BUILD_ROOT/dist" \
  "CL Audio Controller.spec"


echo "========== BUILD CL SHOWCUE =========="
"$CL_PYTHON" -m PyInstaller \
  --noconfirm \
  --workpath "$BUILD_ROOT/build-showcue" \
  --distpath "$BUILD_ROOT/dist" \
  "CL ShowCue.spec"

echo "========== BUILD CL CUE EDITOR =========="
"$CL_PYTHON" -m PyInstaller \
  --noconfirm \
  --workpath "$BUILD_ROOT/build-cue-editor" \
  --distpath "$BUILD_ROOT/dist" \
  "CL ShowCue Builder.spec"

echo "========== BUILD CL AUDIO EXPORT =========="
"$CL_PYTHON" -m PyInstaller \
  --noconfirm \
  --workpath "$BUILD_ROOT/build-audio-export" \
  --distpath "$BUILD_ROOT/dist" \
  "CL Show Audio Builder.spec"


echo "========== BUILD CL ARRANGEMENT BUILDER =========="
BUILDER_BUILD="$BUILD_ROOT/arrangement-builder"
mkdir -p "$BUILDER_BUILD"

(
  cd "$BUILDER_DIR"
  "$CL_PYTHON" -m PyInstaller \
    --noconfirm \
    --workpath "$BUILDER_BUILD/work" \
    --distpath "$BUILDER_BUILD/dist" \
    "Arrangement Builder Live.spec"
)

BUILDER_APP="$BUILDER_BUILD/dist/CL Arrangement Builder.app"

if [[ ! -d "$BUILDER_APP" ]]; then
  echo "Bundle CL Arrangement Builder introuvable : $BUILDER_APP" >&2
  exit 1
fi

ditto "$PROJECT_ROOT/assets/app_icons/CL_Ableton.icns"   "$BUILDER_APP/Contents/Resources/CL_Ableton.icns"

/usr/libexec/PlistBuddy   -c "Set :CFBundleIconFile CL_Ableton.icns"   "$BUILDER_APP/Contents/Info.plist"

xattr -cr "$BUILDER_APP"
codesign --force --deep --sign - "$BUILDER_APP"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Bundle introuvable après construction : $APP_PATH" >&2
  exit 1
fi

for required_app in   "$BUILD_ROOT/dist/CL ShowCue.app"   "$BUILD_ROOT/dist/CL Cue Editor.app"   "$BUILD_ROOT/dist/CL Audio Export.app"   "$BUILDER_APP"
do
  if [[ ! -d "$required_app" ]]; then
    echo "Application attendue introuvable après construction : $required_app" >&2
    exit 1
  fi
done

if [[ ! -d "$M4L_SOURCE" ]]; then
  echo "Dossier Max for Live introuvable : $M4L_SOURCE" >&2
  exit 1
fi
if [[ ! -f "$MIDI_DEVICE_SOURCE/CL MIDI Console Monitor.amxd" ]]; then
  echo "CL MIDI Console Monitor introuvable : $MIDI_DEVICE_SOURCE" >&2
  exit 1
fi

echo
"$APP_PATH/Contents/MacOS/CL Audio Controller" --check-showcue-runtime

echo "========== KIT D'INSTALLATION =========="
mkdir -p \
  "$KIT_ROOT/AbletonOSC CL/AbletonOSC" \
  "$KIT_ROOT/Documentation"

ditto "$APP_PATH" "$KIT_ROOT/CL Show Control.app"

ditto "$BUILD_ROOT/dist/CL ShowCue.app" "$KIT_ROOT/CL ShowCue.app"
ditto "$BUILD_ROOT/dist/CL Cue Editor.app" "$KIT_ROOT/CL Cue Editor.app"
ditto "$BUILD_ROOT/dist/CL Audio Export.app" "$KIT_ROOT/CL Audio Export.app"
ditto "$BUILDER_APP" "$KIT_ROOT/CL Arrangement Builder.app"

mkdir -p "$KIT_ROOT/Ableton Live 11-12/Remote Scripts"
ditto "$BUILDER_DIR/RemoteScript"   "$KIT_ROOT/Ableton Live 11-12/Remote Scripts/CL_Arrangement_Builder_Live"
ditto "$M4L_SOURCE" "$KIT_ROOT/Max for Live à installer"
ditto "$MIDI_DEVICE_SOURCE" "$KIT_ROOT/Max for Live à installer/CL MIDI Console Monitor"

"$MIDI_TOOLS_SOURCE/build.sh" "$BUILD_ROOT/midi-tools"

# === CL COMPLETE DESKTOP KIT APPS ===
echo
echo "========== APPLICATIONS DESKTOP SUPPLÉMENTAIRES =========="

REMOTE_BUILD_DIR="$BUILD_ROOT/remote-native"
mkdir -p "$REMOTE_BUILD_DIR"

clang \
  -arch arm64 \
  -arch x86_64 \
  -mmacosx-version-min=10.15 \
  -fobjc-arc \
  -framework Cocoa \
  -framework WebKit \
  "$PACKAGING_SOURCE/RemoteAbleton.m" \
  -o "$REMOTE_BUILD_DIR/RemoteAbleton"

make_native_app \
  "$REMOTE_BUILD_DIR/RemoteAbleton" \
  "$KIT_ROOT/CL Ableton Remote.app" \
  "RemoteAbleton" \
  "CL Ableton Remote" \
  "com.claudio.ableton-remote" \
  "$PROJECT_ROOT/assets/app_icons/CL_Remote.icns"

make_native_app \
  "$BUILD_ROOT/midi-tools/CLMIDIAnalyzer" \
  "$KIT_ROOT/CL MIDI Analyzer.app" \
  "CLMIDIAnalyzer" \
  "CL MIDI Analyzer" \
  "com.claudio.midi-analyzer" \
  "$PROJECT_ROOT/assets/app_icons/CL_MIDI_Analyzer.icns" \
  "$PROJECT_ROOT/M4L/Devices/CL MIDI Console Monitor/paradis_latin_logo.jpg"

make_native_app \
  "$BUILD_ROOT/midi-tools/CLMIDIPerformanceMonitor" \
  "$KIT_ROOT/CL MIDI Performance Monitor.app" \
  "CLMIDIPerformanceMonitor" \
  "CL MIDI Performance Monitor" \
  "com.claudio.midi-performance-monitor" \
  "$PROJECT_ROOT/assets/app_icons/CL_MIDI_Performance.icns"

make_native_app \
  "$BUILD_ROOT/midi-tools/CLAudioConfigurationChecker" \
  "$KIT_ROOT/CL MIDI & RTP Diagnostic.app" \
  "CLAudioConfigurationChecker" \
  "CL MIDI &amp; RTP Diagnostic" \
  "com.claudio.configurationchecker" \
  "$PROJECT_ROOT/assets/app_icons/CL_MIDI_RTP_Diagnostic.icns" \
  "$PROJECT_ROOT/M4L/Devices/CL MIDI Console Monitor/paradis_latin_logo.jpg"

for binary in \
  "$KIT_ROOT/CL Ableton Remote.app/Contents/MacOS/RemoteAbleton" \
  "$KIT_ROOT/CL MIDI Analyzer.app/Contents/MacOS/CLMIDIAnalyzer" \
  "$KIT_ROOT/CL MIDI Performance Monitor.app/Contents/MacOS/CLMIDIPerformanceMonitor" \
  "$KIT_ROOT/CL MIDI & RTP Diagnostic.app/Contents/MacOS/CLAudioConfigurationChecker"
do
  verify_universal "$binary"
done
mkdir -p \
  "$KIT_ROOT/CL MIDI Network Tools" \
  "$KIT_ROOT/CL MIDI Network Manager.app/Contents/MacOS" \
  "$KIT_ROOT/CL MIDI Network Manager.app/Contents/Resources/Network Tools" \
  "$KIT_ROOT/CL MIDI RTP Agent.app/Contents/MacOS" \
  "$KIT_ROOT/CL MIDI RTP Agent.app/Contents/Resources"
ditto "$PROJECT_ROOT/assets/app_icons/CL_MIDI_RTP.icns" "$KIT_ROOT/CL MIDI RTP Agent.app/Contents/Resources/CL_MIDI_RTP.icns"
for tool in CLMIDINetworkGuardian CLMIDIRTPAgent CLMIDIDirectBridge CLMIDIRoundTripTester CLMIDIRTPResponder CLYamahaConsoleSimulator CLMIDINetworkDashboard CLAudioConfigurationChecker; do
  verify_universal "$BUILD_ROOT/midi-tools/$tool"
  sign_universal_binary "$BUILD_ROOT/midi-tools/$tool"
  /usr/bin/codesign --verify --strict "$BUILD_ROOT/midi-tools/$tool"

  ditto "$BUILD_ROOT/midi-tools/$tool" "$KIT_ROOT/CL MIDI Network Tools/$tool"
  ditto "$BUILD_ROOT/midi-tools/$tool" "$KIT_ROOT/CL MIDI Network Manager.app/Contents/Resources/Network Tools/$tool"

  chmod +x     "$KIT_ROOT/CL MIDI Network Tools/$tool"     "$KIT_ROOT/CL MIDI Network Manager.app/Contents/Resources/Network Tools/$tool"

  /usr/bin/codesign --verify --strict     "$KIT_ROOT/CL MIDI Network Tools/$tool"
  /usr/bin/codesign --verify --strict     "$KIT_ROOT/CL MIDI Network Manager.app/Contents/Resources/Network Tools/$tool"
done
ditto "$BUILD_ROOT/midi-tools/CLMIDIRTPAgent" "$KIT_ROOT/CL MIDI RTP Agent.app/Contents/MacOS/CL MIDI RTP Agent"
ditto "$BUILD_ROOT/midi-tools/CLMIDIDirectBridge" "$KIT_ROOT/CL MIDI RTP Agent.app/Contents/MacOS/CLMIDIDirectBridge"
chmod +x "$KIT_ROOT/CL MIDI RTP Agent.app/Contents/MacOS/CL MIDI RTP Agent"
chmod +x "$KIT_ROOT/CL MIDI RTP Agent.app/Contents/MacOS/CLMIDIDirectBridge"
cat > "$KIT_ROOT/CL MIDI RTP Agent.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>CL MIDI RTP Agent</string>
<key>CFBundleExecutable</key><string>CL MIDI RTP Agent</string>
<key>CFBundleIdentifier</key><string>com.claudio.midi-rtp-agent</string>
<key>CFBundleName</key><string>CL MIDI RTP Agent</string>
<key>CFBundleIconFile</key><string>CL_MIDI_RTP.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>LSBackgroundOnly</key><true/>
<key>LSMinimumSystemVersion</key><string>10.15</string>
</dict></plist>
EOF
xattr -cr "$KIT_ROOT/CL MIDI RTP Agent.app"
codesign --force --deep --sign - "$KIT_ROOT/CL MIDI RTP Agent.app"
codesign --verify --deep --strict "$KIT_ROOT/CL MIDI RTP Agent.app"
ditto "$MIDI_TOOLS_SOURCE/reconnect_legacy_rtp.applescript" "$KIT_ROOT/CL MIDI Network Tools/reconnect_legacy_rtp.applescript"
ditto "$MIDI_TOOLS_SOURCE/reconnect_legacy_rtp.applescript" "$KIT_ROOT/CL MIDI Network Manager.app/Contents/Resources/Network Tools/reconnect_legacy_rtp.applescript"
ditto "$MIDI_TOOLS_SOURCE/connect_rtp_peer.applescript" "$KIT_ROOT/CL MIDI Network Tools/connect_rtp_peer.applescript"
ditto "$MIDI_TOOLS_SOURCE/connect_rtp_peer.applescript" "$KIT_ROOT/CL MIDI Network Manager.app/Contents/Resources/Network Tools/connect_rtp_peer.applescript"
ditto "$MIDI_TOOLS_SOURCE/list_rtp_peers.applescript" "$KIT_ROOT/CL MIDI Network Tools/list_rtp_peers.applescript"
ditto "$MIDI_TOOLS_SOURCE/list_rtp_peers.applescript" "$KIT_ROOT/CL MIDI Network Manager.app/Contents/Resources/Network Tools/list_rtp_peers.applescript"
ditto "$MIDI_TOOLS_SOURCE/open_rtp_settings.applescript" "$KIT_ROOT/CL MIDI Network Tools/open_rtp_settings.applescript"
ditto "$MIDI_TOOLS_SOURCE/open_rtp_settings.applescript" "$KIT_ROOT/CL MIDI Network Manager.app/Contents/Resources/Network Tools/open_rtp_settings.applescript"
ditto "$BUILD_ROOT/midi-tools/CLMIDINetworkDashboard" "$KIT_ROOT/CL MIDI Network Manager.app/Contents/MacOS/CL MIDI Network Assistant"
ditto "$PACKAGING_SOURCE/CL_MIDI_Network_Assistant.sh" "$KIT_ROOT/CL MIDI Network Manager.app/Contents/Resources/LegacyAssistant.sh"
ditto "$PROJECT_ROOT/assets/app_icons/CL_MIDI_Network.icns" "$KIT_ROOT/CL MIDI Network Manager.app/Contents/Resources/CL_MIDI_Network_Assistant.icns"
ditto "$PROJECT_ROOT/M4L/Devices/CL MIDI Console Monitor/paradis_latin_logo.jpg" "$KIT_ROOT/CL MIDI Network Manager.app/Contents/Resources/paradis_latin_logo.jpg"
chmod +x "$KIT_ROOT/CL MIDI Network Tools"/CLMIDI* "$KIT_ROOT/CL MIDI Network Manager.app/Contents/MacOS/CL MIDI Network Assistant" "$KIT_ROOT/CL MIDI Network Manager.app/Contents/Resources/LegacyAssistant.sh"
cat > "$KIT_ROOT/CL MIDI Network Manager.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>CL MIDI Network Manager</string>
<key>CFBundleExecutable</key><string>CL MIDI Network Assistant</string>
<key>CFBundleIdentifier</key><string>com.claudio.midi-network-assistant</string>
<key>CFBundleIconFile</key><string>CL_MIDI_Network_Assistant.icns</string>
<key>CFBundleName</key><string>CL MIDI Network Manager</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>10.15</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>CL MIDI Network Manager utilise Configuration audio et MIDI et Événements système pour ouvrir et reconnecter la cible RTP sélectionnée.</string>
</dict></plist>
EOF
xattr -cr "$KIT_ROOT/CL MIDI Network Manager.app"
codesign --force --deep --sign - "$KIT_ROOT/CL MIDI Network Manager.app"

# git archive n'inclut ni .git, ni caches, ni journaux, ni fichiers locaux.
git -C "$ABLETONOSC_ROOT" archive --format=tar HEAD |
  tar -xf - -C "$KIT_ROOT/AbletonOSC CL/AbletonOSC"

cp "$PACKAGING_SOURCE/Installer_CL_Audio_Controller.command" "$KIT_ROOT/Installer la Suite CL.command"
cp "$PACKAGING_SOURCE/Verifier_SHA256.command" "$KIT_ROOT/"
cp "$PACKAGING_SOURCE/INSTALLATION_NOUVEAU_MAC.txt" "$KIT_ROOT/LISEZ_MOI_INSTALLATION.txt"
cp "$PROJECT_ROOT/README.md" "$KIT_ROOT/Documentation/README.md"
cp "$PROJECT_ROOT/BUILD_ENVIRONMENT.md" "$KIT_ROOT/Documentation/BUILD_ENVIRONMENT.md"
cp "$PROJECT_ROOT/THIRD_PARTY_LICENSES.md" "$KIT_ROOT/Documentation/THIRD_PARTY_LICENSES.md"
cp "$PROJECT_ROOT/LICENSE" "$KIT_ROOT/Documentation/LICENSE"
chmod +x \
  "$KIT_ROOT/Installer la Suite CL.command" \
  "$KIT_ROOT/Verifier_SHA256.command"


echo
echo "========== ORGANISATION DU KIT =========="

PRIMARY_DIR="$KIT_ROOT/01 — Applications principales"
PRODUCTION_DIR="$KIT_ROOT/02 — Production"
MIDI_DIR="$KIT_ROOT/03 — MIDI & Réseau"
ABLETON_DIR="$KIT_ROOT/04 — Ableton & Max for Live"
SHOWCUE_DATA_DIR="$KIT_ROOT/05 — Données ShowCue"
SHOWCUE_SESSIONS_SOURCE="$PROJECT_ROOT/CL_Transport/ShowCue_Sessions"

[[ -d "$SHOWCUE_SESSIONS_SOURCE" ]] || {
  echo "Sessions ShowCue officielles absentes : $SHOWCUE_SESSIONS_SOURCE" >&2
  exit 1
}

mkdir -p \
  "$PRIMARY_DIR" \
  "$PRODUCTION_DIR" \
  "$MIDI_DIR" \
  "$ABLETON_DIR" \
  "$SHOWCUE_DATA_DIR"

for app in \
  "CL Show Control.app" \
  "CL ShowCue.app" \
  "CL Cue Editor.app"
do
  [[ -d "$KIT_ROOT/$app" ]] || {
    echo "Application principale absente : $app" >&2
    exit 1
  }
  mv "$KIT_ROOT/$app" "$PRIMARY_DIR/$app"
done

for app in \
  "CL Arrangement Builder.app" \
  "CL Audio Export.app" \
  "CL Ableton Remote.app"
do
  [[ -d "$KIT_ROOT/$app" ]] || {
    echo "Application Production absente : $app" >&2
    exit 1
  }
  mv "$KIT_ROOT/$app" "$PRODUCTION_DIR/$app"
done

for app in \
  "CL MIDI Network Manager.app" \
  "CL MIDI RTP Agent.app" \
  "CL MIDI & RTP Diagnostic.app" \
  "CL MIDI Analyzer.app" \
  "CL MIDI Performance Monitor.app"
do
  [[ -d "$KIT_ROOT/$app" ]] || {
    echo "Application MIDI/Réseau absente : $app" >&2
    exit 1
  }
  mv "$KIT_ROOT/$app" "$MIDI_DIR/$app"
done

if [[ -d "$KIT_ROOT/CL MIDI Network Tools" ]]; then
  mv "$KIT_ROOT/CL MIDI Network Tools" "$MIDI_DIR/CL MIDI Network Tools"
fi

echo
echo "========== VALIDATION SIGNATURES MIDI/RÉSEAU =========="

for tool in CLMIDINetworkGuardian CLMIDIRTPAgent CLMIDIDirectBridge CLMIDIRoundTripTester CLMIDIRTPResponder CLYamahaConsoleSimulator CLMIDINetworkDashboard CLAudioConfigurationChecker; do
  for binary in     "$MIDI_DIR/CL MIDI Network Tools/$tool"     "$MIDI_DIR/CL MIDI Network Manager.app/Contents/Resources/Network Tools/$tool"
  do
    verify_universal "$binary"
    /usr/bin/codesign --verify --strict "$binary"
  done
done

/usr/bin/codesign --verify --deep --strict   "$MIDI_DIR/CL MIDI Network Manager.app"
/usr/bin/codesign --verify --deep --strict   "$MIDI_DIR/CL MIDI RTP Agent.app"

echo
echo "========== NETTOYAGE XATTR FINAL =========="

while IFS= read -r -d '' app; do
  /usr/bin/xattr -cr "$app"
  /usr/bin/codesign --verify --deep --strict "$app"
done < <(/usr/bin/find "$KIT_ROOT" -type d -name "*.app" -print0)

if /usr/bin/xattr -lr "$KIT_ROOT" 2>/dev/null | /usr/bin/grep -q 'com.apple.quarantine'; then
  echo "ERREUR : com.apple.quarantine encore présent dans le kit final" >&2
  /usr/bin/xattr -lr "$KIT_ROOT" 2>/dev/null | /usr/bin/grep -B2 -A2 'com.apple.quarantine' >&2 || true
  exit 1
fi

for item in \
  "AbletonOSC CL" \
  "Ableton Live 11-12" \
  "Max for Live à installer"
do
  if [[ -e "$KIT_ROOT/$item" ]]; then
    mv "$KIT_ROOT/$item" "$ABLETON_DIR/$item"
  fi
done

echo
echo "========== CONDUITES SHOWCUE =========="

for session in \
  "Oiseau de Paradis.showcue" \
  "Mon Premier Cabaret.showcue"
do
  source_session="$SHOWCUE_SESSIONS_SOURCE/$session"

  [[ -f "$source_session" ]] || {
    echo "Conduite ShowCue officielle absente : $source_session" >&2
    exit 1
  }

  /usr/bin/ditto     "$source_session"     "$SHOWCUE_DATA_DIR/$session"
done

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
    "01 — Applications principales/CL Show Control.app/Contents/MacOS/CL Audio Controller" \
    "04 — Ableton & Max for Live/AbletonOSC CL/AbletonOSC/abletonosc/song.py" \
    "04 — Ableton & Max for Live/Max for Live à installer/XFADER OSC BRIDGE v8.amxd" \
    "04 — Ableton & Max for Live/Max for Live à installer/LTC Display v2.0 Remote Config.amxd" \
    "04 — Ableton & Max for Live/Max for Live à installer/Paradis Latin AutoScene.amxd" \
    "04 — Ableton & Max for Live/Max for Live à installer/Paradis Latin AutoScene - Live 10.amxd" \
    "04 — Ableton & Max for Live/Max for Live à installer/Paradis Latin AutoScene - Live 10.maxpat" \
    "04 — Ableton & Max for Live/Max for Live à installer/CL MIDI Console Monitor/CL MIDI Console Monitor.amxd" \
    "03 — MIDI & Réseau/CL MIDI Network Tools/CLMIDIRoundTripTester" \
    > CONTENU_SHA256.txt
)

"$CL_PYTHON" "$PROJECT_ROOT/scripts/verify_macos_architectures.py" "$KIT_ROOT" --target "$CL_BUILD_ARCH" --report "$KIT_ROOT/ARCHITECTURES.json"

if [[ "${MINIMAL_RELEASE:-0}" != "1" && "$SKIP_DMG" != "1" ]]; then
  echo
  echo "========== DMG =========="
  hdiutil create \
    -volname "CL Audio Controller $VERSION" \
    -srcfolder "$KIT_ROOT" \
    -format UDZO \
    "$RELEASE_DIR/$DMG_NAME"
fi

echo
echo "========== ZIP COMPLET =========="
ditto -c -k --sequesterRsrc --keepParent \
  "$KIT_ROOT" \
  "$RELEASE_DIR/$ZIP_NAME"

if [[ "${MINIMAL_RELEASE:-0}" != "1" ]]; then
  echo
  echo "========== ZIP MAX FOR LIVE =========="
  ditto -c -k --sequesterRsrc --keepParent \
    "$KIT_ROOT/04 — Ableton & Max for Live/Max for Live à installer" \
    "$RELEASE_DIR/$M4L_ZIP_NAME"
fi

echo
echo "========== SHA-256 =========="
(
  cd "$RELEASE_DIR"

  if [[ "${MINIMAL_RELEASE:-0}" == "1" ]]; then
    checksum_files=("$ZIP_NAME")
  else
    checksum_files=("$ZIP_NAME" "$M4L_ZIP_NAME")
    [[ "$SKIP_DMG" == "1" ]] || checksum_files=("$DMG_NAME" "${checksum_files[@]}")
  fi

  shasum -a 256 "${checksum_files[@]}" > SHA256SUMS.txt
)

cat > "$RELEASE_DIR/BUILD_INFO.txt" <<EOF
CL Audio Controller $VERSION
Git commit: $(git rev-parse HEAD)
Built at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Build workspace: $BUILD_ROOT
Build host architecture: $(uname -m)
Target architecture: $CL_BUILD_ARCH
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
