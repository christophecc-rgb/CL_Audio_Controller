#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_HOME="${CL_SUITE_INSTALL_HOME:-$HOME}"
USER_APPS="$INSTALL_HOME/Applications"
ABLETON_LIBRARY="$INSTALL_HOME/Music/Ableton/User Library"
REMOTE_SCRIPTS="$ABLETON_LIBRARY/Remote Scripts"
M4L_REMOTE_TARGET="$ABLETON_LIBRARY/Presets/Audio Effects/Max Audio Effect/CL Audio Controller - Remote"
M4L_AUTOSCENE_TARGET="$ABLETON_LIBRARY/Presets/Audio Effects/Max Audio Effect/CL Audio Controller - AutoScene"
M4L_LIVE10_TARGET="$ABLETON_LIBRARY/Presets/Audio Effects/Max Audio Effect/CL Audio Controller - Live 10"
STAMP="$(date '+%Y-%m-%d_%H%M%S')"
WORK_DIR="$(mktemp -d "/private/tmp/CL_Suite_Installer_XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

fail() {
  echo
  echo "ERREUR : $1" >&2
  exit 1
}

require_source() {
  [[ -e "$1" ]] || fail "élément absent du kit : $1"
}

backup_existing() {
  local target="$1"
  if [[ -e "$target" || -L "$target" ]]; then
    local backup="${target}.sauvegarde_${STAMP}"
    [[ ! -e "$backup" ]] || fail "sauvegarde déjà existante : $backup"
    echo "  Sauvegarde : $backup"
    mv "$target" "$backup"
  fi
}

install_item() {
  local source="$1"
  local target="$2"
  local label="$3"
  require_source "$source"
  echo
  echo "$label"
  backup_existing "$target"
  mkdir -p "$(dirname "$target")"
  ditto "$source" "$target"
  echo "  Installé : $target"
}

CONTROLLER_ZIP="$(find "$SCRIPT_DIR/01 - CL Audio Controller "* -maxdepth 1 -type f -name 'CL_Audio_Controller_*_Kit_Complet_macOS.zip' -print -quit 2>/dev/null || true)"
BUILDER_ROOT="$SCRIPT_DIR/02 - CL Arrangement Builder Live 1.2.2/Arrangement Builder Live 1.2.2"

[[ -n "$CONTROLLER_ZIP" ]] || fail "ZIP complet de CL Audio Controller introuvable"
require_source "$BUILDER_ROOT/Applications/Arrangement Builder Live.app"
require_source "$BUILDER_ROOT/Installation Ableton/Remote Scripts/CL_Arrangement_Builder_Live"

echo "============================================================"
echo " INSTALLER TOUTE LA SUITE CL"
echo "============================================================"
echo
echo "Fermez complètement Ableton Live avant de continuer."
echo "Aucun mot de passe administrateur n'est nécessaire."
echo

if [[ "${CL_SUITE_NONINTERACTIVE:-0}" != "1" ]]; then
  read -r -p "Continuer ? (o/n) " answer
  case "$answer" in
    o|O|oui|OUI|y|Y|yes|YES) ;;
    *) echo "Installation annulée."; exit 0 ;;
  esac
fi

LIVE_FAMILY="${CL_SUITE_LIVE_FAMILY:-}"
if [[ -z "$LIVE_FAMILY" ]]; then
  echo "Version d'Ableton Live :"
  echo "  1 — Live 11 ou Live 12"
  echo "  2 — Live 10"
  echo "  3 — Annuler"
  read -r -p "Votre choix : " LIVE_FAMILY
fi
case "$LIVE_FAMILY" in
  1|11|12|11-12) LIVE_FAMILY="11-12" ;;
  2|10) LIVE_FAMILY="10" ;;
  *) echo "Installation annulée."; exit 0 ;;
esac

INSTALL_REMOTE=0
INSTALL_BUILDER=0
INSTALL_AUTOSCENE=0
INSTALL_AUTOSCENE_LIVE10=0

if [[ "$LIVE_FAMILY" == "10" ]]; then
  INSTALL_AUTOSCENE_LIVE10=1
else
  COMPONENT_CHOICE="${CL_SUITE_COMPONENTS:-}"
  if [[ -z "$COMPONENT_CHOICE" ]]; then
    echo
    echo "Composants à installer pour Live 11/12 :"
    echo "  1 — Suite complète"
    echo "  2 — Télécommande CL Audio uniquement"
    echo "  3 — Arrangement Builder uniquement"
    echo "  4 — AutoScene uniquement"
    echo "  5 — Choix personnalisé"
    echo "  6 — Annuler"
    read -r -p "Votre choix : " COMPONENT_CHOICE
  fi

  case "$COMPONENT_CHOICE" in
    1|all|complete)
      INSTALL_REMOTE=1; INSTALL_BUILDER=1; INSTALL_AUTOSCENE=1 ;;
    2|remote)
      INSTALL_REMOTE=1 ;;
    3|builder)
      INSTALL_BUILDER=1 ;;
    4|autoscene)
      INSTALL_AUTOSCENE=1 ;;
    5|custom)
      read -r -p "Installer la Télécommande CL Audio ? (o/n) " choice
      [[ "$choice" =~ ^([oOyY]|oui|OUI|yes|YES)$ ]] && INSTALL_REMOTE=1
      read -r -p "Installer Arrangement Builder ? (o/n) " choice
      [[ "$choice" =~ ^([oOyY]|oui|OUI|yes|YES)$ ]] && INSTALL_BUILDER=1
      read -r -p "Installer AutoScene ? (o/n) " choice
      [[ "$choice" =~ ^([oOyY]|oui|OUI|yes|YES)$ ]] && INSTALL_AUTOSCENE=1
      ;;
    remote,builder|builder,remote)
      INSTALL_REMOTE=1; INSTALL_BUILDER=1 ;;
    remote,autoscene|autoscene,remote)
      INSTALL_REMOTE=1; INSTALL_AUTOSCENE=1 ;;
    builder,autoscene|autoscene,builder)
      INSTALL_BUILDER=1; INSTALL_AUTOSCENE=1 ;;
    *) echo "Installation annulée."; exit 0 ;;
  esac
fi

echo
echo "Préparation des fichiers…"
ditto -x -k "$CONTROLLER_ZIP" "$WORK_DIR/controller"
CONTROLLER_ROOT="$(find "$WORK_DIR/controller" -maxdepth 1 -type d -name 'CL Audio Controller *' -print -quit)"
[[ -n "$CONTROLLER_ROOT" ]] || fail "contenu de CL Audio Controller introuvable après extraction"

require_source "$CONTROLLER_ROOT/Max for Live à installer"
if [[ "$INSTALL_REMOTE" == "1" ]]; then
  require_source "$CONTROLLER_ROOT/CL Audio Controller.app"
  require_source "$CONTROLLER_ROOT/AbletonOSC CL/AbletonOSC"
fi

mkdir -p "$USER_APPS" "$REMOTE_SCRIPTS" "$(dirname "$M4L_REMOTE_TARGET")"

if [[ "$INSTALL_REMOTE" == "1" ]]; then
  install_item "$CONTROLLER_ROOT/CL Audio Controller.app" \
    "$USER_APPS/CL Audio Controller.app" "Télécommande — CL Audio Controller"
  install_item "$CONTROLLER_ROOT/AbletonOSC CL/AbletonOSC" \
    "$REMOTE_SCRIPTS/AbletonOSC" "Télécommande — AbletonOSC CL"

  REMOTE_M4L_SOURCE="$WORK_DIR/Max for Live - Remote"
  mkdir -p "$REMOTE_M4L_SOURCE"
  for required in \
    "XFADER OSC BRIDGE v8.amxd" \
    "LTC Display v2.0 Remote Config.amxd" \
    "cache.js"; do
    require_source "$CONTROLLER_ROOT/Max for Live à installer/$required"
    ditto "$CONTROLLER_ROOT/Max for Live à installer/$required" "$REMOTE_M4L_SOURCE/$required"
  done
  install_item "$REMOTE_M4L_SOURCE" "$M4L_REMOTE_TARGET" \
    "Télécommande — LTC et X-Fader"
fi

if [[ "$INSTALL_BUILDER" == "1" ]]; then
  install_item "$BUILDER_ROOT/Applications/Arrangement Builder Live.app" \
    "$USER_APPS/Arrangement Builder Live.app" "Builder — Application"
  install_item \
    "$BUILDER_ROOT/Installation Ableton/Remote Scripts/CL_Arrangement_Builder_Live" \
    "$REMOTE_SCRIPTS/CL_Arrangement_Builder_Live" \
    "Builder — Remote Script"
fi

if [[ "$INSTALL_AUTOSCENE" == "1" ]]; then
  AUTOSCENE_SOURCE="$WORK_DIR/Max for Live - AutoScene"
  mkdir -p "$AUTOSCENE_SOURCE"
  for required in \
    "Paradis Latin AutoScene.amxd" \
    "ParadisLatin_AutoScene.js" \
    "paradis_latin_logo.jpg"; do
    require_source "$CONTROLLER_ROOT/Max for Live à installer/$required"
    ditto "$CONTROLLER_ROOT/Max for Live à installer/$required" "$AUTOSCENE_SOURCE/$required"
  done
  install_item "$AUTOSCENE_SOURCE" "$M4L_AUTOSCENE_TARGET" \
    "AutoScene — Version Live 11/12"
fi

if [[ "$INSTALL_AUTOSCENE_LIVE10" == "1" ]]; then
  LIVE10_SOURCE="$WORK_DIR/Max for Live - Live 10"
  mkdir -p "$LIVE10_SOURCE"
  for required in \
    "Paradis Latin AutoScene - Live 10.amxd" \
    "ParadisLatin_AutoScene.js" \
    "paradis_latin_logo.jpg"; do
    require_source "$CONTROLLER_ROOT/Max for Live à installer/$required"
    ditto "$CONTROLLER_ROOT/Max for Live à installer/$required" "$LIVE10_SOURCE/$required"
  done
  install_item "$LIVE10_SOURCE" "$M4L_LIVE10_TARGET" \
    "AutoScene — Version Live 10"
fi

echo
echo "============================================================"
echo " INSTALLATION TERMINÉE"
echo "============================================================"
echo "Applications : $USER_APPS"
echo "Remote Scripts : $REMOTE_SCRIPTS"
echo "Max for Live : $(dirname "$M4L_REMOTE_TARGET")"
if [[ "$LIVE_FAMILY" == "10" ]]; then
  echo "Max for Live : $M4L_LIVE10_TARGET"
fi
echo
if [[ "$INSTALL_REMOTE" == "1" ]]; then
  echo "Relancez Ableton Live puis sélectionnez AbletonOSC et, si"
  echo "nécessaire, les autres surfaces de contrôle installées."
elif [[ "$LIVE_FAMILY" == "10" ]]; then
  echo "AbletonOSC n'a pas été installé car vous avez choisi Live 10."
fi

if [[ "${CL_SUITE_NONINTERACTIVE:-0}" != "1" && "$INSTALL_REMOTE" == "1" ]]; then
  open -R "$USER_APPS/CL Audio Controller.app" >/dev/null 2>&1 || true
  read -r -p "Appuyez sur Entrée pour fermer cette fenêtre." _
fi
