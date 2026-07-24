#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-2.1.0}"
STAMP="$(date +"%Y-%m-%d_%H-%M-%S")"
RELEASE_ROOT="$PROJECT_ROOT/Releases"
RELEASE_DIR="$RELEASE_ROOT/CL_Audio_Controller_${VERSION}_${STAMP}"
BUILD_ROOT="$(mktemp -d "/private/tmp/CL_Audio_Controller_release_${VERSION}_XXXXXX")"
APP_PATH="$BUILD_ROOT/dist/CL Audio Controller.app"
DMG_STAGING="$BUILD_ROOT/dmg"
M4L_SOURCE="$PROJECT_ROOT/M4L/Install"
M4L_FOLDER_NAME="Max for Live à installer"
DMG_NAME="CL_Audio_Controller_${VERSION}.dmg"
ZIP_NAME="CL_Audio_Controller_${VERSION}_macOS.zip"
M4L_ZIP_NAME="CL_Audio_Controller_${VERSION}_Max_for_Live.zip"

if [[ -e "$RELEASE_DIR" ]]; then
  echo "Refus d'écraser une distribution existante : $RELEASE_DIR" >&2
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

mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
cp -R "$M4L_SOURCE" "$DMG_STAGING/$M4L_FOLDER_NAME"
cp -R "$M4L_SOURCE" "$RELEASE_DIR/$M4L_FOLDER_NAME"

echo
echo "========== DMG =========="
hdiutil create \
  -volname "CL Audio Controller $VERSION" \
  -srcfolder "$DMG_STAGING" \
  -format UDZO \
  "$RELEASE_DIR/$DMG_NAME"

echo
echo "========== ZIP =========="
ditto -c -k --sequesterRsrc --keepParent \
  "$APP_PATH" \
  "$RELEASE_DIR/$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent \
  "$RELEASE_DIR/$M4L_FOLDER_NAME" \
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
EOF

echo
echo "✅ Distribution créée sans remplacer les précédentes :"
echo "$RELEASE_DIR"
ls -lh "$RELEASE_DIR"
echo
cat "$RELEASE_DIR/SHA256SUMS.txt"
