#!/bin/bash
set -euo pipefail
KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
if pgrep -f '/Contents/MacOS/(Live|CL Audio Controller)' >/dev/null; then
  echo "Fermez Ableton Live et CL Show Control avant l’installation."
  read -r -p "Appuyez sur Entrée pour fermer… " _
  exit 1
fi
SCRIPTS_DIR="$HOME/Music/Ableton/User Library/Remote Scripts"
if [[ -d "$HOME/Music/Ableton/User Library /Remote Scripts" ]]; then
  SCRIPTS_DIR="$HOME/Music/Ableton/User Library /Remote Scripts"
fi
echo "Installation de CL Show Control autonome."
echo "Remote Scripts : $SCRIPTS_DIR"
read -r -p "Autre dossier Remote Scripts (Entrée pour conserver celui-ci) : " CUSTOM_SCRIPTS
if [[ -n "$CUSTOM_SCRIPTS" ]]; then SCRIPTS_DIR="$CUSTOM_SCRIPTS"; fi
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$HOME/Applications" "$SCRIPTS_DIR"
APP_TARGET="$HOME/Applications/CL Show Control.app"
if [[ -e "$APP_TARGET" ]]; then mv "$APP_TARGET" "$HOME/Applications/CL Show Control avant autonome $STAMP.app"; fi
if [[ -e "$SCRIPTS_DIR/AbletonOSC" ]]; then mv "$SCRIPTS_DIR/AbletonOSC" "$SCRIPTS_DIR/../AbletonOSC-avant-autonome-$STAMP"; fi
ditto "$KIT_DIR/CL Show Control.app" "$APP_TARGET"
ditto "$KIT_DIR/AbletonOSC" "$SCRIPTS_DIR/AbletonOSC"
echo "Installé. Relancez Live et sélectionnez la surface de contrôle AbletonOSC."
echo "Puis ouvrez CL Show Control dans votre dossier Applications."
read -r -p "Appuyez sur Entrée pour fermer… " _
