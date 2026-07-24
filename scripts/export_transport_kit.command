#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASES_DIR="$PROJECT_DIR/Releases"
DESKTOP_DIR="$HOME/Desktop"

if [ ! -d "$RELEASES_DIR" ]; then
  echo "Erreur : dossier Releases introuvable : $RELEASES_DIR"
  exit 1
fi

LATEST_ENTRY="$(
  find "$RELEASES_DIR" -maxdepth 1 -type f -name 'CL_Production_Suite_*.zip' \
    -exec stat -f '%m %N' {} \; |
    sort -nr |
    head -n 1
)"

if [ -z "$LATEST_ENTRY" ]; then
  echo "Erreur : aucun kit CL_Production_Suite_*.zip trouvé dans :"
  echo "$RELEASES_DIR"
  exit 1
fi

SOURCE_ZIP="${LATEST_ENTRY#* }"
TIMESTAMP="$(date '+%Y-%m-%d_%H%M%S')"
DEST_ZIP="$DESKTOP_DIR/CL_Suite_Transport_${TIMESTAMP}.zip"
DEST_SHA="$DESKTOP_DIR/CL_Suite_Transport_${TIMESTAMP}_SHA256.txt"

echo "Kit source :"
echo "$SOURCE_ZIP"
echo
echo "Création de la copie transportable…"
ditto "$SOURCE_ZIP" "$DEST_ZIP"

EXPECTED_SHA="$(shasum -a 256 "$SOURCE_ZIP" | awk '{print $1}')"
COPIED_SHA="$(shasum -a 256 "$DEST_ZIP" | awk '{print $1}')"

if [ "$EXPECTED_SHA" != "$COPIED_SHA" ]; then
  echo "Erreur : la copie ne possède pas la même empreinte SHA-256."
  exit 1
fi

printf '%s  %s\n' "$COPIED_SHA" "$(basename "$DEST_ZIP")" > "$DEST_SHA"

echo
echo "Kit prêt :"
echo "$DEST_ZIP"
echo
echo "SHA-256 :"
echo "$COPIED_SHA"

open -R "$DEST_ZIP"
osascript -e 'display notification "Le ZIP complet est prêt sur le Bureau." with title "CL Audio Controller"' >/dev/null 2>&1 || true
