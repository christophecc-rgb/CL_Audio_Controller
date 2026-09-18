#!/bin/bash
set -euo pipefail

export CL_BUILD_ARCH="${CL_BUILD_ARCH:-universal2}"
case "$CL_BUILD_ARCH" in
  arm64|x86_64|universal2) ;;
  *) echo "Architecture invalide : $CL_BUILD_ARCH" >&2; exit 2 ;;
esac

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
export CL_PYTHON="${CL_PYTHON:-$PROJECT_DIR/.venv/bin/python}"
BUILDER_DIR="$GITHUB_DIR/CL_Arrangement_Builder_Live"
ABLETONOSC_DIR="$GITHUB_DIR/AbletonOSC"
RELEASES_DIR="$PROJECT_DIR/Releases"
DESKTOP_DIR="${CL_SUITE_EXPORT_DIR:-$HOME/Desktop}"
ICLOUD_DRIVE_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
VERSION="${CL_AUDIO_VERSION:-2.2.0}"
TIMESTAMP="$(date '+%Y-%m-%d_%H%M%S')"
SUITE_NAME="CL_Suite_Transport_${TIMESTAMP}_${CL_BUILD_ARCH}"
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
require_file "$BUILDER_DIR/Arrangement Builder Live.spec"
require_dir "$BUILDER_DIR/RemoteScript"
require_dir "$PROJECT_DIR/M4L/Install"
require_file "$PROJECT_DIR/scripts/build_release.sh"
require_file "$PROJECT_DIR/CL Show Audio Builder.spec"
require_file "$PROJECT_DIR/show_audio_builder_desktop.py"
require_file "$PROJECT_DIR/show_audio.json"
require_file "$PROJECT_DIR/vendor/ffmpeg/macos/ffmpeg"
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
CL_RELEASE_OUTPUT_ROOT="$CONTROLLER_RELEASES" CL_RELEASE_SKIP_DMG=1 \
  "$PROJECT_DIR/scripts/build_release.sh" "$VERSION"
CONTROLLER_RELEASE="$(find "$CONTROLLER_RELEASES" -maxdepth 1 -type d -name "CL_Audio_Controller_${VERSION}_*" -print -quit)"
[[ -n "$CONTROLLER_RELEASE" ]] || fail "la nouvelle distribution CL Audio Controller est introuvable"

require_file "$CONTROLLER_RELEASE/CL_Audio_Controller_${VERSION}_Kit_Complet_macOS.zip"
require_file "$CONTROLLER_RELEASE/CL_Audio_Controller_${VERSION}_Max_for_Live.zip"

CONTROLLER_EXTRACT="$BUILD_ROOT/controller-extract"
ditto -x -k "$CONTROLLER_RELEASE/CL_Audio_Controller_${VERSION}_Kit_Complet_macOS.zip" "$CONTROLLER_EXTRACT"
CONTROLLER_ROOT="$(find "$CONTROLLER_EXTRACT" -maxdepth 1 -type d -name 'CL Audio Controller *' -print -quit)"
[[ -n "$CONTROLLER_ROOT" ]] || fail "contenu du kit CL Audio Controller introuvable"

echo
echo "Construction d’CL Arrangement Builder depuis les sources actuelles…"
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
[[ -d "$BUILDER_APP" ]] || fail "la nouvelle application CL Arrangement Builder est introuvable"
ditto "$PROJECT_DIR/assets/app_icons/CL_Ableton.icns" "$BUILDER_APP/Contents/Resources/CL_Ableton.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile CL_Ableton.icns" "$BUILDER_APP/Contents/Info.plist"
xattr -cr "$BUILDER_APP"
codesign --force --deep --sign - "$BUILDER_APP"

echo
echo "Construction de CL Audio Export ($CL_BUILD_ARCH) depuis les sources actuelles…"
SHOW_AUDIO_BUILD="$BUILD_ROOT/show-audio-builder"
mkdir -p "$SHOW_AUDIO_BUILD"

(
  cd "$PROJECT_DIR"
  "$CL_PYTHON" -m PyInstaller     --clean     --noconfirm     --workpath "$SHOW_AUDIO_BUILD/work"     --distpath "$SHOW_AUDIO_BUILD/dist"     "CL Show Audio Builder.spec"
)

SHOW_AUDIO_APP="$SHOW_AUDIO_BUILD/dist/CL Audio Export.app"
[[ -d "$SHOW_AUDIO_APP" ]] || fail "la nouvelle application CL Audio Export est introuvable"

SHOW_AUDIO_EXE="$SHOW_AUDIO_APP/Contents/MacOS/CL Show Audio Builder"
SHOW_AUDIO_FFMPEG="$SHOW_AUDIO_APP/Contents/Frameworks/ffmpeg"

require_file "$SHOW_AUDIO_EXE"
require_file "$SHOW_AUDIO_FFMPEG"

"$CL_PYTHON" "$PROJECT_DIR/scripts/verify_macos_architectures.py" "$SHOW_AUDIO_APP" --target "$CL_BUILD_ARCH"
codesign --verify --deep --strict "$SHOW_AUDIO_APP" || fail "signature de CL Audio Export invalide"

echo "Construction des fenêtres ShowCue depuis le working tree courant…"
for showcue_name in "CL ShowCue" "CL Cue Editor"; do
  showcue_spec="$showcue_name"
  [[ "$showcue_name" != "CL Cue Editor" ]] || showcue_spec="CL ShowCue Builder"
  "${CL_PYTHON:-$PROJECT_DIR/.venv/bin/python}" -m PyInstaller --noconfirm \
    --workpath "$BUILD_ROOT/showcue-work/$showcue_name" \
    --distpath "$BUILD_ROOT/showcue-dist" "$PROJECT_DIR/$showcue_spec.spec"
  codesign --verify --deep --strict "$BUILD_ROOT/showcue-dist/$showcue_name.app"
done
"$PROJECT_DIR/scripts/build_cl_transport.command" "$SUITE_ROOT/CL_Transport" \
  --sessions "$PROJECT_DIR/CL_Transport/ShowCue_Sessions"

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
  "$COMPONENTS_ROOT/Outils_reseau_MIDI" \
  "$INSTALLER_RESOURCES/Documentation" \
  "$UNINSTALLER_APP/Contents/MacOS" \
  "$UNINSTALLER_APP/Contents/Resources"

echo
echo "Assemblage des applications et composants…"
ditto "$CONTROLLER_ROOT/01 — Applications principales/CL Show Control.app" "$COMPONENTS_ROOT/Applications/CL Show Control.app"
ditto "$CONTROLLER_ROOT/02 — Production/CL Ableton Remote.app" "$COMPONENTS_ROOT/Applications/CL Ableton Remote.app"
ditto "$SHOW_AUDIO_APP" "$COMPONENTS_ROOT/Applications/CL Audio Export.app"
for showcue_name in "CL ShowCue" "CL Cue Editor"; do
  ditto "$BUILD_ROOT/showcue-dist/$showcue_name.app" "$COMPONENTS_ROOT/Applications/$showcue_name.app"
done
ditto "$SUITE_ROOT/CL_Transport" "$COMPONENTS_ROOT/CL_Transport"

ditto "$CONTROLLER_ROOT/03 — MIDI & Réseau/CL MIDI Network Manager.app" "$COMPONENTS_ROOT/Applications/CL MIDI Network Manager.app"
ditto "$CONTROLLER_ROOT/03 — MIDI & Réseau/CL MIDI RTP Agent.app" "$COMPONENTS_ROOT/Applications/CL MIDI RTP Agent.app"
ditto "$CONTROLLER_ROOT/03 — MIDI & Réseau/CL MIDI & RTP Diagnostic.app" "$COMPONENTS_ROOT/Applications/CL MIDI & RTP Diagnostic.app"
ditto "$CONTROLLER_ROOT/03 — MIDI & Réseau/CL MIDI Analyzer.app" "$COMPONENTS_ROOT/Applications/CL MIDI Analyzer.app"
ditto "$CONTROLLER_ROOT/03 — MIDI & Réseau/CL MIDI Performance Monitor.app" "$COMPONENTS_ROOT/Applications/CL MIDI Performance Monitor.app"
ditto "$BUILDER_APP" "$COMPONENTS_ROOT/Applications/CL Arrangement Builder.app"

ditto "$CONTROLLER_ROOT/04 — Ableton & Max for Live/AbletonOSC CL/AbletonOSC" "$COMPONENTS_ROOT/Ableton Live 11-12/Remote Scripts/AbletonOSC"
ditto "$BUILDER_DIR/RemoteScript" "$COMPONENTS_ROOT/Ableton Live 11-12/Remote Scripts/CL_Arrangement_Builder_Live"

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
ditto "$CONTROLLER_ROOT/03 — MIDI & Réseau/CL MIDI Network Tools" "$COMPONENTS_ROOT/Outils_reseau_MIDI"

# Les caches trouvés dans d'anciens livrables Builder ne sont jamais requis à
# l'exécution. Ils sont retirés uniquement de la copie temporaire distribuée.
find "$COMPONENTS_ROOT" -type d -name '__pycache__' -prune -exec rm -r {} +
find "$COMPONENTS_ROOT" -type f \( -name '*.pyc' -o -name '.DS_Store' -o -name '._*' \) -delete

# Le nettoyage ci-dessus peut retirer des ressources qui étaient présentes au
# moment de la signature initiale d'une application (par exemple les .pyc du
# RemoteScript d'Arrangement Builder). Re-signer les applications distribuées
# après le nettoyage afin que leur sceau corresponde exactement au contenu final.
echo "Re-signature des applications après nettoyage…"
while IFS= read -r -d '' app_path; do
  xattr -cr "$app_path"
  codesign --force --deep --sign - "$app_path" || \
    fail "re-signature impossible : $app_path"
  codesign --verify --deep --strict "$app_path" || \
    fail "signature invalide après nettoyage : $app_path"
done < <(find "$COMPONENTS_ROOT/Applications" -type d -name '*.app' -print0)

cp "$PROJECT_DIR/packaging/BUILD_UNIVERSAL2.md" "$INSTALLER_RESOURCES/Documentation/BUILD_UNIVERSAL2.md"
cp "$PROJECT_DIR/README.md" "$INSTALLER_RESOURCES/Documentation/README_CL_Audio_Controller.md"
cp "$PROJECT_DIR/packaging/INSTALLATION_NOUVEAU_MAC.txt" "$INSTALLER_RESOURCES/Documentation/INSTALLATION_NOUVEAU_MAC.txt"
cp "$PROJECT_DIR/packaging/INSTALLATION_AUTOSCENE_LIVE_10.txt" "$INSTALLER_RESOURCES/Documentation/INSTALLATION_AUTOSCENE_LIVE_10.txt"
cp "$PROJECT_DIR/packaging/Installer_Toute_La_Suite_CL.command" "$INSTALLER_RESOURCES/Installer_Toute_La_Suite_CL.command"
cp "$PROJECT_DIR/assets/app_icons/CL_Install.icns" "$INSTALLER_RESOURCES/CL_AUDIO.icns"

cp "$PROJECT_DIR/packaging/Desinstaller_La_Suite_CL.command" "$UNINSTALLER_APP/Contents/Resources/Desinstaller_La_Suite_CL.command"
cp "$PROJECT_DIR/assets/app_icons/CL_Uninstall.icns" "$UNINSTALLER_APP/Contents/Resources/CL_AUDIO.icns"

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
ditto "$NATIVE_BUILD/installer-universal" "$UNINSTALLER_APP/Contents/MacOS/CLSuiteUninstaller"

for resources_dir in "$INSTALLER_RESOURCES" "$UNINSTALLER_APP/Contents/Resources"; do
  ditto "$PROJECT_DIR/assets/app_icons/CL_Audio_Show_Control.png" "$resources_dir/Controller.png"
  ditto "$PROJECT_DIR/assets/app_icons/CL_Audio_Export.png" "$resources_dir/AudioExport.png"
  ditto "$PROJECT_DIR/assets/app_icons/CL_ShowCue.png" "$resources_dir/ShowCue.png"
  ditto "$PROJECT_DIR/assets/app_icons/CL_Cue_Editor.png" "$resources_dir/CueEditor.png"
  ditto "$PROJECT_DIR/assets/app_icons/CL_Ableton.png" "$resources_dir/Builder.png"
  ditto "$PROJECT_DIR/assets/paradis latin.jpg" "$resources_dir/ParadisLatin.jpg"
  ditto "$PROJECT_DIR/assets/app_icons/CL_MIDI_Network.png" "$resources_dir/MIDIConsole.png"
  ditto "$PROJECT_DIR/assets/app_icons/CL_MIDI_RTP_Diagnostic.png" "$resources_dir/Diagnostic.png"
done
chmod +x \
  "$INSTALLER_RESOURCES/Installer_Toute_La_Suite_CL.command" \
  "$INSTALLER_APP/Contents/MacOS/Installer la Suite CL" \
  "$UNINSTALLER_APP/Contents/Resources/Desinstaller_La_Suite_CL.command" \
  "$UNINSTALLER_APP/Contents/MacOS/CLSuiteUninstaller"

for app_kind in installer uninstaller; do
  if [[ "$app_kind" == installer ]]; then
    plist="$INSTALLER_APP/Contents/Info.plist"
    display_name="Installer la Suite CL"
    executable="Installer la Suite CL"
    identifier="com.claudio.suite-installer"
  else
    plist="$UNINSTALLER_APP/Contents/Info.plist"
    display_name="Désinstaller la Suite CL"
    executable="CLSuiteUninstaller"
    identifier="com.claudio.suite-uninstaller"
  fi
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>$display_name</string>
<key>CFBundleExecutable</key><string>$executable</string>
<key>CFBundleIconFile</key><string>CL_AUDIO.icns</string>
<key>CFBundleIdentifier</key><string>$identifier</string>
<key>CFBundleName</key><string>$display_name</string>
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

# clang ajoute une signature ad hoc au seul exécutable. Une fois celui-ci placé
# dans le bundle, macOS attend toutefois une signature couvrant aussi le
# Info.plist et les ressources. Sans cette étape, Gatekeeper peut présenter
# l'application reçue par AirDrop comme « endommagée ».
for app_path in "$INSTALLER_APP" "$UNINSTALLER_APP"; do
  xattr -cr "$app_path"
  codesign --force --sign - "$app_path"
  codesign --verify --deep --strict "$app_path" || \
    fail "signature locale invalide : $app_path"
done

cat > "$SUITE_ROOT/LISEZ_MOI_EN_PREMIER.txt" <<EOF
SUITE CL TRANSPORTABLE — ${TIMESTAMP}
====================================

COMPATIBILITÉ

Architecture : $CL_BUILD_ARCH
Suite complète : macOS 12 Monterey ou ultérieur (FFmpeg embarqué).
Aucune installation Python ou Homebrew sur le Mac cible.

CONTENU VISIBLE

- Installer la Suite CL.app
- Désinstaller la Suite CL.app
- ce guide et le contrôle SHA-256

Les applications, Remote Scripts, périphériques Max for Live et outils MIDI
nécessaires sont contenus dans l'installateur. Aucun DMG ou ZIP intermédiaire
n'est à ouvrir manuellement.

INSTALLATION AUTOMATIQUE

Double-cliquer sur « Installer la Suite CL.app » puis choisir :
- Ableton Live 12 pour sélectionner librement CL Audio Controller,
  CL Audio Export, Arrangement Builder, AutoScene et CL MIDI Console Monitor ;
- Ableton Live 10 pour installer uniquement la variante AutoScene compatible.

Les installations existantes et leurs anciennes sauvegardes sont déplacées dans
une session datée de la Corbeille avant remplacement. Elles restent récupérables.

DÉSINSTALLATION

Double-cliquer sur « Désinstaller la Suite CL.app ». Le désinstallateur propose
les mêmes composants séparément et déplace uniquement les éléments enregistrés
par l'installateur dans la Corbeille. Il ne touche jamais aux Live Sets.

COMMITS

CL Audio Controller : $(git -C "$PROJECT_DIR" rev-parse HEAD)
CL Arrangement Builder : $(git -C "$BUILDER_DIR" rev-parse HEAD)
AbletonOSC CL : $(git -C "$ABLETONOSC_DIR" rev-parse HEAD)

IMPORTANT

- Fermer Ableton Live avant l'installation.
- Les fichiers .adv personnels ne sont pas inclus. Les .amxd portables validés
  et leurs dépendances nécessaires sont intégrés à l'installateur.
- Cette distribution n'est pas encore notarisée par Apple.
- Au premier lancement sur un autre Mac, faire un clic droit sur
  « Installer la Suite CL.app », choisir « Ouvrir », puis confirmer « Ouvrir ».
- Si macOS bloque encore l'application, utiliser « Ouvrir quand même » dans
  Réglages Système > Confidentialité et sécurité.
EOF

(
  cd "$SUITE_ROOT"
  find . -type f ! -name 'SHA256SUMS.txt' -print0 |
    sort -z |
    xargs -0 shasum -a 256 > SHA256SUMS.txt
)

echo
"$CL_PYTHON" "$PROJECT_DIR/scripts/verify_app_identity.py" "$SUITE_ROOT" --suite
"$CL_PYTHON" "$PROJECT_DIR/scripts/verify_macos_architectures.py" "$SUITE_ROOT" \
  --target "$CL_BUILD_ARCH" --report "$SUITE_ROOT/ARCHITECTURES.json"
# Include the architecture report in the checksum manifest as well.
(cd "$SUITE_ROOT"; shasum -a 256 ARCHITECTURES.json >> SHA256SUMS.txt)
echo "Création du ZIP sur le Bureau…"
ditto -c -k --norsrc --keepParent "$SUITE_ROOT" "$BUILD_ROOT/final-kit.zip"

echo "Vérification du ZIP après ré-extraction…"
ROUNDTRIP_ROOT="$BUILD_ROOT/roundtrip-check"
rm -rf "$ROUNDTRIP_ROOT"
mkdir -p "$ROUNDTRIP_ROOT"
ditto -x -k "$BUILD_ROOT/final-kit.zip" "$ROUNDTRIP_ROOT"

ROUNDTRIP_SUITE="$(find "$ROUNDTRIP_ROOT" -maxdepth 1 -type d -name 'CL_Suite_Transport_*' -print -quit)"
[[ -n "$ROUNDTRIP_SUITE" ]] || fail "suite ré-extraite introuvable"

ROUNDTRIP_INSTALLER="$ROUNDTRIP_SUITE/Installer la Suite CL.app"
ROUNDTRIP_UNINSTALLER="$ROUNDTRIP_SUITE/Désinstaller la Suite CL.app"

codesign --verify --deep --strict "$ROUNDTRIP_INSTALLER" ||   fail "signature de l’installateur cassée après archivage/ré-extraction"

codesign --verify --deep --strict "$ROUNDTRIP_UNINSTALLER" ||   fail "signature du désinstallateur cassée après archivage/ré-extraction"

ZIP_SHA="$(shasum -a 256 "$BUILD_ROOT/final-kit.zip" | awk '{print $1}')"
printf '%s  %s\n' "$ZIP_SHA" "$(basename "$DEST_ZIP")" > "$BUILD_ROOT/final-kit-sha.txt"

# Contrôle final : le ZIP doit contenir tous les éléments essentiels.
ZIP_LIST="$BUILD_ROOT/zip_contents.txt"
unzip -Z1 "$BUILD_ROOT/final-kit.zip" > "$ZIP_LIST"
for expected in \
  "Installer la Suite CL.app/" \
  "Désinstaller la Suite CL.app/" \
  "Installer la Suite CL.app/Contents/Resources/Composants/Applications/CL Show Control.app/" \
  "Installer la Suite CL.app/Contents/Resources/Composants/Applications/CL Audio Export.app/" \
  "Installer la Suite CL.app/Contents/Resources/Composants/Applications/CL Audio Export.app/Contents/Frameworks/ffmpeg" \
  "Installer la Suite CL.app/Contents/Resources/Composants/Applications/CL MIDI & RTP Diagnostic.app/" \
  "Installer la Suite CL.app/Contents/Resources/Composants/Applications/CL MIDI Analyzer.app/" \
  "Installer la Suite CL.app/Contents/Resources/Composants/Applications/CL MIDI Performance Monitor.app/" \
  "Installer la Suite CL.app/Contents/Resources/Composants/Applications/CL Arrangement Builder.app/" \
  "Installer la Suite CL.app/Contents/Resources/Composants/Ableton Live 11-12/Remote Scripts/AbletonOSC/" \
  "Installer la Suite CL.app/Contents/Resources/Composants/Ableton Live 11-12/Remote Scripts/CL_Arrangement_Builder_Live/" \
  "XFADER OSC BRIDGE v8.amxd" \
  "LTC Display v2.0 Remote Config.amxd" \
  "Paradis Latin AutoScene.amxd" \
  "Paradis Latin AutoScene - Live 10.amxd" \
  "CL MIDI Console Monitor.amxd" \
  "CL MIDI Network Manager.app/" \
  "CL MIDI RTP Agent.app/" \
  "CLMIDIRoundTripTester"; do
  LC_ALL=C grep -aFq "$expected" "$ZIP_LIST" || fail "contrôle final impossible, élément absent du ZIP : $expected"
done

for unwanted in '.DS_Store' '__pycache__' '.pyc' '.dmg' '_Max_for_Live.zip' '_Kit_Complet_macOS.zip' '__MACOSX/'; do
  if LC_ALL=C grep -aFq "$unwanted" "$ZIP_LIST"; then
    fail "fichier inutile détecté dans le kit final : $unwanted"
  fi
done

[[ ! -e "$DEST_ZIP" && ! -e "$DEST_SHA" ]] || fail "destination déjà existante : $DEST_ZIP"
mkdir -p "$DESKTOP_DIR"
ditto "$BUILD_ROOT/final-kit.zip" "$DEST_ZIP"
ditto "$BUILD_ROOT/final-kit-sha.txt" "$DEST_SHA"

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
