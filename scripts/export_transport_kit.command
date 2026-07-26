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
DESKTOP_DIR="$HOME/Desktop"
ICLOUD_DRIVE_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
VERSION="${CL_AUDIO_VERSION:-2.2.0}"
TIMESTAMP="$(date '+%Y-%m-%d_%H%M%S')"
SUITE_NAME="CL_Suite_Transport_${TIMESTAMP}"
BUILD_ROOT="$(mktemp -d "/private/tmp/${SUITE_NAME}_XXXXXX")"
SUITE_ROOT="$BUILD_ROOT/$SUITE_NAME"
DEST_ZIP="$DESKTOP_DIR/${SUITE_NAME}.zip"
DEST_SHA="$DESKTOP_DIR/${SUITE_NAME}_SHA256.txt"
ICLOUD_DEST_ZIP="$ICLOUD_DRIVE_DIR/${SUITE_NAME}.zip"

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

for required in \
  "XFADER OSC BRIDGE v8.amxd" \
  "LTC Display v2.0 Remote Config.amxd" \
  "Paradis Latin AutoScene.amxd" \
  "Paradis Latin AutoScene - Live 10.amxd" \
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

BEFORE_LIST="$BUILD_ROOT/releases_before.txt"
AFTER_LIST="$BUILD_ROOT/releases_after.txt"
find "$RELEASES_DIR" -maxdepth 1 -type d -name "CL_Audio_Controller_${VERSION}_*" -print | sort > "$BEFORE_LIST"

"$PROJECT_DIR/scripts/build_release.sh" "$VERSION"

find "$RELEASES_DIR" -maxdepth 1 -type d -name "CL_Audio_Controller_${VERSION}_*" -print | sort > "$AFTER_LIST"
CONTROLLER_RELEASE="$(comm -13 "$BEFORE_LIST" "$AFTER_LIST" | tail -n 1)"
[[ -n "$CONTROLLER_RELEASE" ]] || fail "la nouvelle distribution CL Audio Controller est introuvable"

require_file "$CONTROLLER_RELEASE/CL_Audio_Controller_${VERSION}.dmg"
require_file "$CONTROLLER_RELEASE/CL_Audio_Controller_${VERSION}_Kit_Complet_macOS.zip"
require_file "$CONTROLLER_RELEASE/CL_Audio_Controller_${VERSION}_Max_for_Live.zip"

mkdir -p \
  "$SUITE_ROOT/01 - CL Audio Controller $VERSION" \
  "$SUITE_ROOT/02 - CL Arrangement Builder Live 1.2.2" \
  "$SUITE_ROOT/03 - Max for Live" \
  "$SUITE_ROOT/04 - AbletonOSC CL" \
  "$SUITE_ROOT/Documentation"

echo
echo "Assemblage des applications et composants…"
ditto "$CONTROLLER_RELEASE" "$SUITE_ROOT/01 - CL Audio Controller $VERSION"
ditto \
  "$BUILDER_DIR/release/Arrangement Builder Live 1.2.2" \
  "$SUITE_ROOT/02 - CL Arrangement Builder Live 1.2.2/Arrangement Builder Live 1.2.2"
ditto "$PROJECT_DIR/M4L/Install" "$SUITE_ROOT/03 - Max for Live/À installer"

# Archive propre d'AbletonOSC, sans .git, caches ni fichiers locaux.
git -C "$ABLETONOSC_DIR" archive --format=zip --output="$SUITE_ROOT/04 - AbletonOSC CL/AbletonOSC_CL_Live_11-12.zip" HEAD

cp "$PROJECT_DIR/README.md" "$SUITE_ROOT/Documentation/README_CL_Audio_Controller.md"
cp "$PROJECT_DIR/packaging/INSTALLATION_NOUVEAU_MAC.txt" "$SUITE_ROOT/Documentation/INSTALLATION_NOUVEAU_MAC.txt"
cp "$PROJECT_DIR/packaging/INSTALLATION_AUTOSCENE_LIVE_10.txt" "$SUITE_ROOT/Documentation/INSTALLATION_AUTOSCENE_LIVE_10.txt"
cp "$PROJECT_DIR/packaging/Installer_Toute_La_Suite_CL.command" "$SUITE_ROOT/Installer_Toute_La_Suite_CL.command"
cp "$PROJECT_DIR/packaging/Desinstaller_La_Suite_CL.command" "$SUITE_ROOT/Desinstaller_La_Suite_CL.command"
chmod +x "$SUITE_ROOT/Installer_Toute_La_Suite_CL.command" "$SUITE_ROOT/Desinstaller_La_Suite_CL.command"

cat > "$SUITE_ROOT/LISEZ_MOI_EN_PREMIER.txt" <<EOF
SUITE CL TRANSPORTABLE — ${TIMESTAMP}
====================================

CONTENU

1. CL Audio Controller ${VERSION}
   Application, DMG, ZIP complet et installateur automatique.

2. CL Arrangement Builder Live 1.2.2
   Application et Remote Script Ableton associés.

3. Max for Live
   - XFADER OSC BRIDGE v8
   - LTC Display v2.0 Remote Config
   - Paradis Latin AutoScene (Live actuel)
   - Paradis Latin AutoScene - Live 10
   - fichiers JavaScript et ressources nécessaires

4. AbletonOSC CL
   Version issue du commit $(git -C "$ABLETONOSC_DIR" rev-parse HEAD),
   prévue pour Ableton Live 11 et 12.

INSTALLATION AUTOMATIQUE

Double-cliquer sur Installer_Toute_La_Suite_CL.command puis choisir :
- Live 11/12 pour installer toute la suite, AbletonOSC compris ;
- Live 10 pour installer les applications et périphériques compatibles sans
  installer la version AbletonOSC destinée à Live 11/12.

Les installations existantes sont sauvegardées avec une date avant remplacement.

DÉSINSTALLATION

Double-cliquer sur Desinstaller_La_Suite_CL.command. Le désinstallateur propose
les mêmes composants séparément et déplace uniquement les éléments enregistrés
par l'installateur dans la Corbeille. Il ne touche jamais aux Live Sets.

COMMITS

CL Audio Controller : $(git -C "$PROJECT_DIR" rev-parse HEAD)
CL Arrangement Builder Live : $(git -C "$BUILDER_DIR" rev-parse HEAD)
AbletonOSC CL : $(git -C "$ABLETONOSC_DIR" rev-parse HEAD)

IMPORTANT

- Fermer Ableton Live avant d'installer AbletonOSC ou les Remote Scripts.
- Les fichiers .adv personnels ne sont pas inclus : ils peuvent mémoriser des
  chemins propres à un Mac. Les .amxd portables validés sont fournis.
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
ditto -c -k --sequesterRsrc --keepParent "$SUITE_ROOT" "$DEST_ZIP"

ZIP_SHA="$(shasum -a 256 "$DEST_ZIP" | awk '{print $1}')"
printf '%s  %s\n' "$ZIP_SHA" "$(basename "$DEST_ZIP")" > "$DEST_SHA"

# Contrôle final : le ZIP doit contenir tous les éléments essentiels.
ZIP_LIST="$BUILD_ROOT/zip_contents.txt"
unzip -Z1 "$DEST_ZIP" > "$ZIP_LIST"
for expected in \
  "CL_Audio_Controller_${VERSION}.dmg" \
  "Arrangement Builder Live.app/" \
  "XFADER OSC BRIDGE v8.amxd" \
  "LTC Display v2.0 Remote Config.amxd" \
  "Paradis Latin AutoScene.amxd" \
  "Paradis Latin AutoScene - Live 10.amxd" \
  "AbletonOSC_CL_Live_11-12.zip" \
  "Installer_Toute_La_Suite_CL.command" \
  "Desinstaller_La_Suite_CL.command"; do
  LC_ALL=C grep -aFq "$expected" "$ZIP_LIST" || fail "contrôle final impossible, élément absent du ZIP : $expected"
done

[[ -d "$ICLOUD_DRIVE_DIR" ]] || fail_cloud "iCloud Drive n'est pas disponible sur ce Mac"

echo
echo "Copie du ZIP vers iCloud Drive…"
ditto "$DEST_ZIP" "$ICLOUD_DEST_ZIP" || fail_cloud "la copie du ZIP a échoué"

ICLOUD_ZIP_SHA="$(shasum -a 256 "$ICLOUD_DEST_ZIP" | awk '{print $1}')"
[[ "$ICLOUD_ZIP_SHA" == "$ZIP_SHA" ]] || fail_cloud "la copie iCloud ne correspond pas au ZIP du Bureau"

echo
echo "============================================================"
echo " KIT COMPLET PRÊT"
echo "============================================================"
echo "$DEST_ZIP"
echo "$ICLOUD_DEST_ZIP"
echo
echo "SHA-256 : $ZIP_SHA"
echo
echo "Tous les composants obligatoires ont été contrôlés."
echo "La copie iCloud a été vérifiée et sera synchronisée par iCloud Drive."

open -R "$DEST_ZIP"
osascript -e 'display notification "La suite CL est prête sur le Bureau et dans iCloud Drive." with title "CL Suite"' >/dev/null 2>&1 || true
