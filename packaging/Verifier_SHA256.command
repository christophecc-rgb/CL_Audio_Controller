#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKSUMS="$SCRIPT_DIR/CONTENU_SHA256.txt"

if [ ! -f "$CHECKSUMS" ]; then
  echo "CONTENU_SHA256.txt est introuvable dans :"
  echo "$SCRIPT_DIR"
  read -r -p "Appuyez sur Entrée pour fermer." _
  exit 1
fi

cd "$SCRIPT_DIR"
echo "Vérification des fichiers de distribution…"
echo

failed=0
while IFS= read -r line; do
  expected="${line%%  *}"
  filename="${line#*  }"
  [ -n "$expected" ] || continue
  [ -n "$filename" ] || continue
  if [ ! -f "$filename" ]; then
    echo "ABSENT : $filename"
    failed=1
    continue
  fi
  actual="$(shasum -a 256 "$filename" | awk '{print $1}')"
  if [ "$actual" = "$expected" ]; then
    echo "OK : $filename"
  else
    echo "DIFFÉRENT : $filename"
    failed=1
  fi
done < "$CHECKSUMS"

echo
if [ "$failed" -eq 0 ]; then
  echo "Tous les fichiers sont intègres."
else
  echo "La vérification a détecté une erreur."
fi
read -r -p "Appuyez sur Entrée pour fermer." _
exit "$failed"
