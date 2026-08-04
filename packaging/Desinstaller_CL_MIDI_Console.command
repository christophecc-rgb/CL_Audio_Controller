#!/bin/bash
set -euo pipefail

INSTALL_HOME="${CL_SUITE_INSTALL_HOME:-$HOME}"
TRASH="$INSTALL_HOME/.Trash"
STAMP="$(date '+%Y-%m-%d_%H%M%S')"
TARGETS=(
  "$INSTALL_HOME/Music/Ableton/User Library/Presets/MIDI Effects/Max MIDI Effect/CL MIDI Console Monitor"
  "$INSTALL_HOME/Library/Application Support/CL MIDI Console/Network Tools"
  "$INSTALL_HOME/Applications/CL MIDI Network Assistant.app"
  "$INSTALL_HOME/Library/LaunchAgents/com.claudio.midi-network-monitor.plist"
)

if [[ "$INSTALL_HOME" == "$HOME" && "${CL_SUITE_SKIP_POSTINSTALL:-0}" != "1" ]]; then
  /bin/launchctl bootout "gui/$(id -u)/com.claudio.midi-network-monitor" >/dev/null 2>&1 || true
fi

echo "CL MIDI CONSOLE — DÉSINSTALLATION"
echo "Les éléments installés seront déplacés dans la Corbeille."
if [[ "${CL_MIDI_NONINTERACTIVE:-0}" != "1" ]]; then
  read -r -p "Continuer ? (o/n) " answer
  [[ "$answer" =~ ^([oOyY]|oui|OUI|yes|YES)$ ]] || exit 0
fi

mkdir -p "$TRASH"
for target in "${TARGETS[@]}"; do
  if [[ -e "$target" && ! -L "$target" ]]; then
    destination="$TRASH/$(basename "$target")_${STAMP}"
    mv "$target" "$destination"
    echo "Déplacé : $destination"
  elif [[ -L "$target" ]]; then
    echo "Ignoré (lien symbolique) : $target"
  fi
done

echo "Désinstallation terminée. Les sauvegardes datées existantes sont conservées."
