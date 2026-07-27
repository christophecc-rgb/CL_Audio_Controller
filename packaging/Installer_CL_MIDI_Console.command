#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_HOME="${CL_SUITE_INSTALL_HOME:-$HOME}"
ABLETON_TARGET="$INSTALL_HOME/Music/Ableton/User Library/Presets/MIDI Effects/Max MIDI Effect/CL MIDI Console Monitor"
TOOLS_TARGET="$INSTALL_HOME/Library/Application Support/CL MIDI Console/Network Tools"
APP_TARGET="$INSTALL_HOME/Applications/CL MIDI Network Assistant.app"
STAMP="$(date '+%Y-%m-%d_%H%M%S')"

fail() {
  echo "ERREUR : $1" >&2
  exit 1
}

backup_existing() {
  local target="$1"
  if [[ -e "$target" || -L "$target" ]]; then
    local backup="${target}.sauvegarde_${STAMP}"
    [[ ! -e "$backup" ]] || fail "sauvegarde déjà existante : $backup"
    mv "$target" "$backup"
    echo "Sauvegarde : $backup"
  fi
}

DEVICE_SOURCE="$SCRIPT_DIR/Max for Live/CL MIDI Console Monitor"
TOOLS_SOURCE="$SCRIPT_DIR/Network Tools"
APP_SOURCE="$SCRIPT_DIR/CL MIDI Network Assistant.app"

[[ -f "$DEVICE_SOURCE/CL MIDI Console Monitor.amxd" ]] || fail "périphérique Max for Live absent"
[[ -x "$TOOLS_SOURCE/CLMIDIRoundTripTester" ]] || fail "outil de test MIDI absent"
[[ -d "$APP_SOURCE" ]] || fail "application d'assistance absente"

echo "CL MIDI CONSOLE — INSTALLATION"
echo "Fermez Ableton Live avant de continuer."
if [[ "${CL_MIDI_NONINTERACTIVE:-0}" != "1" ]]; then
  read -r -p "Continuer ? (o/n) " answer
  [[ "$answer" =~ ^([oOyY]|oui|OUI|yes|YES)$ ]] || exit 0
fi

backup_existing "$ABLETON_TARGET"
backup_existing "$TOOLS_TARGET"
backup_existing "$APP_TARGET"

mkdir -p "$(dirname "$ABLETON_TARGET")" "$(dirname "$TOOLS_TARGET")" "$(dirname "$APP_TARGET")"
ditto "$DEVICE_SOURCE" "$ABLETON_TARGET"
ditto "$TOOLS_SOURCE" "$TOOLS_TARGET"
ditto "$APP_SOURCE" "$APP_TARGET"

chmod 700 "$TOOLS_TARGET"
chmod +x "$TOOLS_TARGET"/CLMIDI* "$APP_TARGET/Contents/MacOS/CL MIDI Network Assistant"

echo
echo "Installation terminée :"
echo "  Max for Live : $ABLETON_TARGET"
echo "  Assistant : $APP_TARGET"
echo "  Outils : $TOOLS_TARGET"
echo
echo "Relancez Ableton Live, puis ajoutez une instance neuve du périphérique."
