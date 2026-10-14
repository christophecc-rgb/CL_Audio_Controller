#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$ROOT/Applications/CL Show Control Light.app"
TARGET="$HOME/Applications/CL Show Control Light.app"
SCRIPT_SOURCE="$ROOT/Ableton/Remote Scripts/AbletonOSC"
SCRIPT_TARGET="$HOME/Music/Ableton/User Library/Remote Scripts/AbletonOSC"
[[ -d "$SOURCE" && -d "$SCRIPT_SOURCE" ]] || { echo 'Kit incomplet'; exit 1; }
read -r -p 'Ableton et Show Control doivent être fermés. Installer Light et AbletonOSC ? [o/N] ' answer
[[ "$answer" == o || "$answer" == O ]] || exit 0
stamp="$(date +%Y%m%d_%H%M%S)"
for target in "$TARGET" "$SCRIPT_TARGET"; do
  if [[ -e "$target" ]]; then
    backup="${target}.sauvegarde_${stamp}"
    [[ ! -e "$backup" ]] || { echo "Sauvegarde existante : $backup"; exit 1; }
    mv "$target" "$backup"
  fi
done
mkdir -p "$(dirname "$TARGET")" "$(dirname "$SCRIPT_TARGET")"
ditto "$SOURCE" "$TARGET"
ditto "$SCRIPT_SOURCE" "$SCRIPT_TARGET"
echo 'Installation terminée. Anciennes copies conservées à côté avec suffixe sauvegarde.'
