#!/bin/bash
set -euo pipefail

# Le fichier du Bureau est un lien symbolique. Résoudre sa cible avant de
# calculer les chemins du dépôt afin que le script fonctionne depuis Finder.
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
  LINK_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
  LINK_TARGET="$(readlink "$SCRIPT_PATH")"
  if [[ "$LINK_TARGET" = /* ]]; then
    SCRIPT_PATH="$LINK_TARGET"
  else
    SCRIPT_PATH="$LINK_DIR/$LINK_TARGET"
  fi
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GITHUB_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
BUILDER_DIR="$GITHUB_DIR/CL_Arrangement_Builder_Live"
ABLETONOSC_DIR="$GITHUB_DIR/AbletonOSC"
RELEASES_DIR="$PROJECT_DIR/Releases"
DESKTOP_DIR="${CL_SUITE_EXPORT_DIR:-$HOME/Desktop}"
ICLOUD_DRIVE_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
VERSION="${CL_AUDIO_VERSION:-2.2.0}"
TIMESTAMP="$(date '+%Y-%m-%d_%H%M%S')"
SUITE_NAME="CL_Suite_Transport_${TIMESTAMP}"
BUILD_ROOT="$(mktemp -d "/private/tmp/${SUITE_NAME}_XXXXXX")"
SUITE_ROOT="$BUILD_ROOT/$SUITE_NAME"
DEST_ZIP="$DESKTOP_DIR/${SUITE_NAME}.zip"
DEST_SHA="$DESKTOP_DIR/${SUITE_NAME}_SHA256.txt"
ICLOUD_DEST_ZIP="$ICLOUD_DRIVE_DIR/${SUITE_NAME}.zip"
SKIP_ICLOUD="${CL_SUITE_SKIP_ICLOUD:-0}"
REVEAL_OUTPUT="${CL_SUITE_REVEAL_OUTPUT:-1}"

cleanup() {
  rm -rf "$BUILD_ROOT"
}
trap cleanup EXIT

fail() {
  echo
  echo "ERREUR : $1" >&2
  echo "Aucun kit incomplet n'a été placé sur le Bureau." >&2
  exit 1
}

fail_cloud() {
  echo
  echo "ERREUR ICLOUD : $1" >&2
  echo "Le kit reste disponible sur le Bureau : $DEST_ZIP" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "fichier obligatoire absent : $1"
}

require_dir() {
  [[ -d "$1" ]] || fail "dossier obligatoire absent : $1"
}

require_dir "$BUILDER_DIR/.git"
require_dir "$ABLETONOSC_DIR/.git"
require_dir "$BUILDER_DIR/release/Arrangement Builder Live 1.2.2"
require_dir "$PROJECT_DIR/M4L/Install"
require_file "$PROJECT_DIR/scripts/build_release.sh"
require_file "$PROJECT_DIR/packaging/CLSuiteInstallerApp.m"
require_file "$PROJECT_DIR/assets/cl_audio_show_control_icon_1024.png"
require_file "$PROJECT_DIR/assets/cl_midi_network_assistant_icon_1024.png"
require_file "$BUILDER_DIR/assets/icon_1024.png"

for required in \
  "XFADER OSC BRIDGE v8.amxd" \
  "LTC Display v2.0 Remote Config.amxd" \
  "Paradis Latin AutoScene.amxd" \
  "Paradis Latin AutoScene - Live 10.amxd" \
  "Paradis Latin AutoScene - Live 10.maxpat" \
  "ParadisLatin_AutoScene.js" \
  "paradis_latin_logo.jpg"; do
  require_file "$PROJECT_DIR/M4L/Install/$required"
done

echo "============================================================"
echo " CRÉATION DE LA SUITE CL TRANSPORTABLE"
echo "============================================================"
echo
echo "Le kit sera reconstruit depuis les sources actuelles."
echo "Il ne réutilisera pas l'ancienne suite du 24 juillet."
echo

CONTROLLER_RELEASES="$BUILD_ROOT/controller-release"
CL_RELEASE_OUTPUT_ROOT="$CONTROLLER_RELEASES" \
  "$PROJECT_DIR/scripts/build_release.sh" "$VERSION"
CONTROLLER_RELEASE="$(find "$CONTROLLER_RELEASES" -maxdepth 1 -type d -name "CL_Audio_Controller_${VERSION}_*" -print -quit)"
[[ -n "$CONTROLLER_RELEASE" ]] || fail "la nouvelle distribution CL Audio Controller est introuvable"

require_file "$CONTROLLER_RELEASE/CL_Audio_Controller_${VERSION}.dmg"
require_file "$CONTROLLER_RELEASE/CL_Audio_Controller_${VERSION}_Kit_Complet_macOS.zip"
require_file "$CONTROLLER_RELEASE/CL_Audio_Controller_${VERSION}_Max_for_Live.zip"

CONTROLLER_EXTRACT="$BUILD_ROOT/controller-extract"
ditto -x -k "$CONTROLLER_RELEASE/CL_Audio_Controller_${VERSION}_Kit_Complet_macOS.zip" "$CONTROLLER_EXTRACT"
CONTROLLER_ROOT="$(find "$CONTROLLER_EXTRACT" -maxdepth 1 -type d -name 'CL Audio Controller *' -print -quit)"
[[ -n "$CONTROLLER_ROOT" ]] || fail "contenu du kit CL Audio Controller introuvable"

INSTALLER_APP="$SUITE_ROOT/Installer la Suite CL.app"
UNINSTALLER_APP="$SUITE_ROOT/Désinstaller la Suite CL.app"
INSTALLER_RESOURCES="$INSTALLER_APP/Contents/Resources"
COMPONENTS_ROOT="$INSTALLER_RESOURCES/Composants"

mkdir -p \
  "$INSTALLER_APP/Contents/MacOS" \
  "$COMPONENTS_ROOT/Applications" \
  "$COMPONENTS_ROOT/Ableton Live 11-12/Remote Scripts" \
  "$COMPONENTS_ROOT/Ableton Live 11-12/Max for Live/CL Audio Controller - Remote" \
  "$COMPONENTS_ROOT/Ableton Live 11-12/Max for Live/Paradis Latin AutoScene" \
  "$COMPONENTS_ROOT/Ableton Live 11-12/Max for Live/CL MIDI Console Monitor" \
  "$COMPONENTS_ROOT/Ableton Live 10/Max for Live/Paradis Latin AutoScene - Live 10" \
  "$COMPONENTS_ROOT/Outils réseau MIDI" \
  "$INSTALLER_RESOURCES/Documentation" \
  "$UNINSTALLER_APP/Contents/MacOS" \
  "$UNINSTALLER_APP/Contents/Resources"

echo
echo "Assemblage des applications et composants…"
ditto "$CONTROLLER_ROOT/CL Audio Controller.app" "$COMPONENTS_ROOT/Applications/CL Audio Controller.app"
ditto "$CONTROLLER_ROOT/CL MIDI Network Assistant.app" "$COMPONENTS_ROOT/Applications/CL MIDI Network Assistant.app"
ditto "$CONTROLLER_ROOT/CL MIDI RTP Agent.app" "$COMPONENTS_ROOT/Applications/CL MIDI RTP Agent.app"
ditto "$CONTROLLER_ROOT/CL MIDI RTP Simulator.app" "$COMPONENTS_ROOT/Applications/CL MIDI RTP Simulator.app"
ditto "$BUILDER_DIR/release/Arrangement Builder Live 1.2.2/Applications/Arrangement Builder Live.app" "$COMPONENTS_ROOT/Applications/Arrangement Builder Live.app"

ditto "$CONTROLLER_ROOT/AbletonOSC CL/AbletonOSC" "$COMPONENTS_ROOT/Ableton Live 11-12/Remote Scripts/AbletonOSC"
ditto "$BUILDER_DIR/release/Arrangement Builder Live 1.2.2/Installation Ableton/Remote Scripts/CL_Arrangement_Builder_Live" "$COMPONENTS_ROOT/Ableton Live 11-12/Remote Scripts/CL_Arrangement_Builder_Live"

for file in "XFADER OSC BRIDGE v8.amxd" "LTC Display v2.0 Remote Config.amxd" cache.js; do
  ditto "$PROJECT_DIR/M4L/Install/$file" "$COMPONENTS_ROOT/Ableton Live 11-12/Max for Live/CL Audio Controller - Remote/$file"
done
for file in "Paradis Latin AutoScene.amxd" ParadisLatin_AutoScene.js paradis_latin_logo.jpg; do
  ditto "$PROJECT_DIR/M4L/Install/$file" "$COMPONENTS_ROOT/Ableton Live 11-12/Max for Live/Paradis Latin AutoScene/$file"
done
for file in "CL MIDI Console Monitor.amxd" "CL MIDI Console Monitor.maxpat" CLMidiConsoleDisplay.js CLMidiConsoleConfirmation.js paradis_latin_logo.jpg; do
  ditto "$PROJECT_DIR/M4L/Devices/CL MIDI Console Monitor/$file" "$COMPONENTS_ROOT/Ableton Live 11-12/Max for Live/CL MIDI Console Monitor/$file"
done
for file in "Paradis Latin AutoScene - Live 10.amxd" "Paradis Latin AutoScene - Live 10.maxpat" ParadisLatin_AutoScene.js paradis_latin_logo.jpg; do
  ditto "$PROJECT_DIR/M4L/Install/$file" "$COMPONENTS_ROOT/Ableton Live 10/Max for Live/Paradis Latin AutoScene - Live 10/$file"
done
ditto "$CONTROLLER_ROOT/CL MIDI Network Tools" "$COMPONENTS_ROOT/Outils réseau MIDI"

# Les caches trouvés dans d'anciens livrables Builder ne sont jamais requis à
# l'exécution. Ils sont retirés uniquement de la copie temporaire distribuée.
find "$COMPONENTS_ROOT" -type d -name '__pycache__' -prune -exec rm -r {} +
find "$COMPONENTS_ROOT" -type f \( -name '*.pyc' -o -name '.DS_Store' -o -name '._*' \) -delete

cp "$PROJECT_DIR/README.md" "$INSTALLER_RESOURCES/Documentation/README_CL_Audio_Controller.md"
cp "$PROJECT_DIR/packaging/INSTALLATION_NOUVEAU_MAC.txt" "$INSTALLER_RESOURCES/Documentation/INSTALLATION_NOUVEAU_MAC.txt"
cp "$PROJECT_DIR/packaging/INSTALLATION_AUTOSCENE_LIVE_10.txt" "$INSTALLER_RESOURCES/Documentation/INSTALLATION_AUTOSCENE_LIVE_10.txt"
cp "$PROJECT_DIR/packaging/Installer_Toute_La_Suite_CL.command" "$INSTALLER_RESOURCES/Installer_Toute_La_Suite_CL.command"
cp "$PROJECT_DIR/CL_AUDIO.icns" "$INSTALLER_RESOURCES/CL_AUDIO.icns"

cp "$PROJECT_DIR/packaging/Desinstaller_La_Suite_CL.command" "$UNINSTALLER_APP/Contents/Resources/Desinstaller_La_Suite_CL.command"
cp "$PROJECT_DIR/CL_AUDIO.icns" "$UNINSTALLER_APP/Contents/Resources/CL_AUDIO.icns"

echo "Compilation de l’interface native de l’installateur…"
NATIVE_BUILD="$BUILD_ROOT/native-installer"
mkdir -p "$NATIVE_BUILD/cache"
CLANG_MODULE_CACHE_PATH="$NATIVE_BUILD/cache" clang -fobjc-arc -target arm64-apple-macosx10.15 \
  -framework Cocoa "$PROJECT_DIR/packaging/CLSuiteInstallerApp.m" \
  -o "$NATIVE_BUILD/installer-arm64"
CLANG_MODULE_CACHE_PATH="$NATIVE_BUILD/cache" clang -fobjc-arc -target x86_64-apple-macosx10.15 \
  -framework Cocoa "$PROJECT_DIR/packaging/CLSuiteInstallerApp.m" \
  -o "$NATIVE_BUILD/installer-x86_64"
lipo -create "$NATIVE_BUILD/installer-arm64" "$NATIVE_BUILD/installer-x86_64" \
  -output "$NATIVE_BUILD/installer-universal"
ditto "$NATIVE_BUILD/installer-universal" "$INSTALLER_APP/Contents/MacOS/Installer la Suite CL"
ditto "$NATIVE_BUILD/installer-universal" "$UNINSTALLER_APP/Contents/MacOS/Désinstaller la Suite CL"

for resources_dir in "$INSTALLER_RESOURCES" "$UNINSTALLER_APP/Contents/Resources"; do
  ditto "$PROJECT_DIR/assets/cl_audio_show_control_icon_1024.png" "$resources_dir/Controller.png"
  ditto "$BUILDER_DIR/assets/icon_1024.png" "$resources_dir/Builder.png"
  ditto "$PROJECT_DIR/assets/paradis latin.jpg" "$resources_dir/ParadisLatin.jpg"
  ditto "$PROJECT_DIR/assets/cl_midi_network_assistant_icon_1024.png" "$resources_dir/MIDIConsole.png"
done
chmod +x \
  "$INSTALLER_RESOURCES/Installer_Toute_La_Suite_CL.command" \
  "$INSTALLER_APP/Contents/MacOS/Installer la Suite CL" \
  "$UNINSTALLER_APP/Contents/Resources/Desinstaller_La_Suite_CL.command" \
  "$UNINSTALLER_APP/Contents/MacOS/Désinstaller la Suite CL"

for app_kind in installer uninstaller; do
  if [[ "$app_kind" == installer ]]; then
    plist="$INSTALLER_APP/Contents/Info.plist"
    executable="Installer la Suite CL"
    identifier="com.claudio.suite-installer"
  else
    plist="$UNINSTALLER_APP/Contents/Info.plist"
    executable="Désinstaller la Suite CL"
    identifier="com.claudio.suite-uninstaller"
  fi
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>$executable</string>
<key>CFBundleExecutable</key><string>$executable</string>
<key>CFBundleIconFile</key><string>CL_AUDIO.icns</string>
<key>CFBundleIdentifier</key><string>$identifier</string>
<key>CFBundleName</key><string>$executable</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>10.15</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
done

(
  cd "$INSTALLER_RESOURCES"
  find Composants -type f -print0 | sort -z | xargs -0 shasum -a 256 > COMPONENTS_SHA256.txt
)

cat > "$SUITE_ROOT/LISEZ_MOI_EN_PREMIER.txt" <<EOF
SUITE CL TRANSPORTABLE — ${TIMESTAMP}
====================================

CONTENU VISIBLE

- Installer la Suite CL.app
- Désinstaller la Suite CL.app
- ce guide et le contrôle SHA-256

Les applications, Remote Scripts, périphériques Max for Live et outils MIDI
nécessaires sont contenus dans l'installateur. Aucun DMG ou ZIP intermédiaire
n'est à ouvrir manuellement.

INSTALLATION AUTOMATIQUE

Double-cliquer sur « Installer la Suite CL.app » puis choisir :
- Ableton Live 12 pour sélectionner librement CL Audio Controller, le Builder,
  AutoScene et CL MIDI Console Monitor ;
- Ableton Live 10 pour installer uniquement la variante AutoScene compatible.

Les installations existantes sont sauvegardées avec une date avant remplacement.

DÉSINSTALLATION

Double-cliquer sur « Désinstaller la Suite CL.app ». Le désinstallateur propose
les mêmes composants séparément et déplace uniquement les éléments enregistrés
par l'installateur dans la Corbeille. Il ne touche jamais aux Live Sets.

COMMITS

CL Audio Controller : $(git -C "$PROJECT_DIR" rev-parse HEAD)
CL Arrangement Builder Live : $(git -C "$BUILDER_DIR" rev-parse HEAD)
AbletonOSC CL : $(git -C "$ABLETONOSC_DIR" rev-parse HEAD)

IMPORTANT

- Fermer Ableton Live avant l'installation.
- Les fichiers .adv personnels ne sont pas inclus. Les .amxd portables validés
  et leurs dépendances nécessaires sont intégrés à l'installateur.
- Cette distribution n'est pas encore notarisée par Apple.
EOF

(
  cd "$SUITE_ROOT"
  find . -type f ! -name 'SHA256SUMS.txt' -print0 |
    sort -z |
    xargs -0 shasum -a 256 > SHA256SUMS.txt
)

echo
echo "Création du ZIP sur le Bureau…"
ditto -c -k --norsrc --keepParent "$SUITE_ROOT" "$DEST_ZIP"

ZIP_SHA="$(shasum -a 256 "$DEST_ZIP" | awk '{print $1}')"
printf '%s  %s\n' "$ZIP_SHA" "$(basename "$DEST_ZIP")" > "$DEST_SHA"

# Contrôle final : le ZIP doit contenir tous les éléments essentiels.
ZIP_LIST="$BUILD_ROOT/zip_contents.txt"
unzip -Z1 "$DEST_ZIP" > "$ZIP_LIST"
for expected in \
  "Installer la Suite CL.app/" \
  "Désinstaller la Suite CL.app/" \
  "Installer la Suite CL.app/Contents/Resources/Composants/Applications/CL Audio Controller.app/" \
  "Installer la Suite CL.app/Contents/Resources/Composants/Applications/Arrangement Builder Live.app/" \
  "Installer la Suite CL.app/Contents/Resources/Composants/Ableton Live 11-12/Remote Scripts/AbletonOSC/" \
  "Installer la Suite CL.app/Contents/Resources/Composants/Ableton Live 11-12/Remote Scripts/CL_Arrangement_Builder_Live/" \
  "XFADER OSC BRIDGE v8.amxd" \
  "LTC Display v2.0 Remote Config.amxd" \
  "Paradis Latin AutoScene.amxd" \
  "Paradis Latin AutoScene - Live 10.amxd" \
  "CL MIDI Console Monitor.amxd" \
  "CL MIDI Network Assistant.app/" \
  "CL MIDI RTP Agent.app/" \
  "CL MIDI RTP Simulator.app/" \
  "CLMIDIRoundTripTester"; do
  LC_ALL=C grep -aFq "$expected" "$ZIP_LIST" || fail "contrôle final impossible, élément absent du ZIP : $expected"
done

for unwanted in '.DS_Store' '__pycache__' '.pyc' '.dmg' '_Max_for_Live.zip' '_Kit_Complet_macOS.zip' '__MACOSX/'; do
  if LC_ALL=C grep -aFq "$unwanted" "$ZIP_LIST"; then
    fail "fichier inutile détecté dans le kit final : $unwanted"
  fi
done

if [[ "$SKIP_ICLOUD" != "1" ]]; then
  [[ -d "$ICLOUD_DRIVE_DIR" ]] || fail_cloud "iCloud Drive n'est pas disponible sur ce Mac"
  echo
  echo "Copie du ZIP vers iCloud Drive…"
  ditto "$DEST_ZIP" "$ICLOUD_DEST_ZIP" || fail_cloud "la copie du ZIP a échoué"
  ICLOUD_ZIP_SHA="$(shasum -a 256 "$ICLOUD_DEST_ZIP" | awk '{print $1}')"
  [[ "$ICLOUD_ZIP_SHA" == "$ZIP_SHA" ]] || fail_cloud "la copie iCloud ne correspond pas au ZIP du Bureau"
fi

echo
echo "============================================================"
echo " KIT COMPLET PRÊT"
echo "============================================================"
echo "$DEST_ZIP"
[[ "$SKIP_ICLOUD" == "1" ]] || echo "$ICLOUD_DEST_ZIP"
echo
echo "SHA-256 : $ZIP_SHA"
echo
echo "Tous les composants obligatoires ont été contrôlés."
if [[ "$SKIP_ICLOUD" == "1" ]]; then
  echo "Validation locale : copie iCloud volontairement désactivée."
else
  echo "La copie iCloud a été vérifiée et sera synchronisée par iCloud Drive."
fi

if [[ "$REVEAL_OUTPUT" == "1" ]]; then
  open -R "$DEST_ZIP"
  osascript -e 'display notification "La suite CL est prête." with title "CL Suite"' >/dev/null 2>&1 || true
fi
