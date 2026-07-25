#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SOURCE="$SCRIPT_DIR/CL Audio Controller.app"
ABLETONOSC_SOURCE="$SCRIPT_DIR/AbletonOSC CL/AbletonOSC"
M4L_SOURCE="$SCRIPT_DIR/Max for Live à installer"

USER_APPS="$HOME/Applications"
APP_TARGET="$USER_APPS/CL Audio Controller.app"
REMOTE_SCRIPTS="$HOME/Music/Ableton/User Library/Remote Scripts"
ABLETONOSC_TARGET="$REMOTE_SCRIPTS/AbletonOSC"
M4L_TARGET="$HOME/Music/Ableton/User Library/Presets/Audio Effects/Max Audio Effect/CL Audio Controller"
STAMP="$(date '+%Y-%m-%d_%H%M%S')"

backup_existing() {
  local target="$1"
  if [ -e "$target" ]; then
    local backup="${target}.sauvegarde_${STAMP}"
    echo "Sauvegarde de l'installation existante :"
    echo "  $backup"
    mv "$target" "$backup"
  fi
}

require_source() {
  local source="$1"
  if [ ! -e "$source" ]; then
    echo "ERREUR : élément absent du kit :"
    echo "  $source"
    exit 1
  fi
}

clear
echo "============================================================"
echo " INSTALLATION CL AUDIO CONTROLLER"
echo "============================================================"
echo
echo "Cette installation ne demande pas de mot de passe administrateur."
echo "Fermez Ableton Live avant de continuer."
echo
read -r -p "Continuer ? (o/n) " answer
case "$answer" in
  o|O|oui|OUI|y|Y|yes|YES) ;;
  *) echo "Installation annulée."; exit 0 ;;
esac

require_source "$APP_SOURCE"
require_source "$ABLETONOSC_SOURCE"
require_source "$M4L_SOURCE"

mkdir -p "$USER_APPS" "$REMOTE_SCRIPTS" "$(dirname "$M4L_TARGET")"

echo
echo "1/3 — Application"
backup_existing "$APP_TARGET"
ditto "$APP_SOURCE" "$APP_TARGET"

echo
echo "2/3 — AbletonOSC CL"
backup_existing "$ABLETONOSC_TARGET"
ditto "$ABLETONOSC_SOURCE" "$ABLETONOSC_TARGET"

echo
echo "3/3 — Périphériques Max for Live"
backup_existing "$M4L_TARGET"
ditto "$M4L_SOURCE" "$M4L_TARGET"

echo
echo "============================================================"
echo " INSTALLATION TERMINÉE"
echo "============================================================"
echo
echo "Application :"
echo "  $APP_TARGET"
echo
echo "AbletonOSC :"
echo "  $ABLETONOSC_TARGET"
echo
echo "Max for Live :"
echo "  $M4L_TARGET"
echo
echo "Relancez Ableton Live puis sélectionnez AbletonOSC comme"
echo "surface de contrôle."
echo
open -R "$APP_TARGET" >/dev/null 2>&1 || true
read -r -p "Appuyez sur Entrée pour fermer cette fenêtre." _
