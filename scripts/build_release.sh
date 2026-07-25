#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-2.2.0}"
STAMP="$(date +"%Y-%m-%d_%H-%M-%S")"
RELEASE_ROOT="$PROJECT_ROOT/Releases"
RELEASE_DIR="$RELEASE_ROOT/CL_Audio_Controller_${VERSION}_${STAMP}"
BUILD_ROOT="$(mktemp -d "/private/tmp/CL_Audio_Controller_release_${VERSION}_XXXXXX")"
APP_PATH="$BUILD_ROOT/dist/CL Audio Controller.app"
KIT_ROOT="$BUILD_ROOT/kit/CL Audio Controller $VERSION"
M4L_SOURCE="$PROJECT_ROOT/M4L/Install"
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

echo
echo "========== KIT D'INSTALLATION =========="
mkdir -p \
  "$KIT_ROOT/AbletonOSC CL/AbletonOSC" \
  "$KIT_ROOT/Documentation"

ditto "$APP_PATH" "$KIT_ROOT/CL Audio Controller.app"
ditto "$M4L_SOURCE" "$KIT_ROOT/Max for Live à installer"

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
Contenu: application autonome + AbletonOSC CL + Max for Live + documentation
Python requis sur le Mac cible: non
EOF

echo
echo "✅ Distribution créée sans remplacer les précédentes :"
echo "$RELEASE_DIR"
ls -lh "$RELEASE_DIR"
echo
cat "$RELEASE_DIR/SHA256SUMS.txt"
