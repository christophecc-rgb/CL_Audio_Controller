#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPONENTS_ROOT="$SCRIPT_DIR/Composants"
INTEGRITY_MANIFEST="$SCRIPT_DIR/COMPONENTS_SHA256.txt"
APPLICATIONS_SOURCE="$COMPONENTS_ROOT/Applications"
LIVE_CURRENT_SOURCE="$COMPONENTS_ROOT/Ableton Live 11-12"
LIVE10_SOURCE_ROOT="$COMPONENTS_ROOT/Ableton Live 10"
MIDI_TOOLS_SOURCE="$COMPONENTS_ROOT/Outils réseau MIDI"
INSTALL_HOME="${CL_SUITE_INSTALL_HOME:-$HOME}"
USER_APPS="$INSTALL_HOME/Applications"
ABLETON_LIBRARY="$INSTALL_HOME/Music/Ableton/User Library"
REMOTE_SCRIPTS="$ABLETON_LIBRARY/Remote Scripts"
M4L_REMOTE_TARGET="$ABLETON_LIBRARY/Presets/Audio Effects/Max Audio Effect/CL Audio Controller - Remote"
M4L_AUTOSCENE_TARGET="$ABLETON_LIBRARY/Presets/Audio Effects/Max Audio Effect/CL Audio Controller - AutoScene"
M4L_LIVE10_TARGET="$ABLETON_LIBRARY/Presets/Audio Effects/Max Audio Effect/CL Audio Controller - Live 10"
M4L_MIDI_CONSOLE_TARGET="$ABLETON_LIBRARY/Presets/MIDI Effects/Max MIDI Effect/CL MIDI Console Monitor"
MIDI_TOOLS_TARGET="$INSTALL_HOME/Library/Application Support/CL MIDI Console/Network Tools"
SUPPORT_DIR="$INSTALL_HOME/Library/Application Support/CL Audio Controller"
INSTALL_MANIFEST="$SUPPORT_DIR/CL_Suite_install_manifest.tsv"
STAMP="$(date '+%Y-%m-%d_%H%M%S')"
WORK_DIR="$(mktemp -d "/private/tmp/CL_Suite_Installer_XXXXXX")"
MANIFEST_UPDATES="$WORK_DIR/manifest_updates.tsv"

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
  local component="$4"
  require_source "$source"
  echo
  echo "$label"
  backup_existing "$target"
  mkdir -p "$(dirname "$target")"
  ditto "$source" "$target"
  echo "  Installé : $target"
  printf '%s\t%s\t%s\n' "$component" "$target" "$STAMP" >> "$MANIFEST_UPDATES"
}

write_install_manifest() {
  local combined="$WORK_DIR/manifest_combined.tsv"
  mkdir -p "$SUPPORT_DIR"
  chmod 700 "$SUPPORT_DIR"
  if [[ -f "$INSTALL_MANIFEST" && ! -L "$INSTALL_MANIFEST" ]]; then
    cat "$INSTALL_MANIFEST" > "$combined"
  elif [[ -L "$INSTALL_MANIFEST" ]]; then
    fail "le manifeste d'installation est un lien symbolique : $INSTALL_MANIFEST"
  else
    : > "$combined"
  fi
  cat "$MANIFEST_UPDATES" >> "$combined"
  awk -F '\t' 'NF == 3 { latest[$1 FS $2] = $0 } END { for (key in latest) print latest[key] }' \
    "$combined" | LC_ALL=C sort > "$INSTALL_MANIFEST.tmp"
  chmod 600 "$INSTALL_MANIFEST.tmp"
  mv "$INSTALL_MANIFEST.tmp" "$INSTALL_MANIFEST"
}

require_source "$COMPONENTS_ROOT"
require_source "$INTEGRITY_MANIFEST"
if ! (cd "$SCRIPT_DIR" && shasum -a 256 -c "$(basename "$INTEGRITY_MANIFEST")" >/dev/null); then
  fail "le contrôle d'intégrité des composants a échoué"
fi

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
INSTALL_MIDI_CONSOLE=0

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
    echo "  5 — CL MIDI Console uniquement"
    echo "  6 — Choix personnalisé"
    echo "  7 — Annuler"
    read -r -p "Votre choix : " COMPONENT_CHOICE
  fi

  case "$COMPONENT_CHOICE" in
    1|all|complete)
      INSTALL_REMOTE=1; INSTALL_BUILDER=1; INSTALL_AUTOSCENE=1; INSTALL_MIDI_CONSOLE=1 ;;
    2|remote)
      INSTALL_REMOTE=1 ;;
    3|builder)
      INSTALL_BUILDER=1 ;;
    4|autoscene)
      INSTALL_AUTOSCENE=1 ;;
    5|midi-console)
      INSTALL_MIDI_CONSOLE=1 ;;
    6|custom)
      read -r -p "Installer la Télécommande CL Audio ? (o/n) " choice
      [[ "$choice" =~ ^([oOyY]|oui|OUI|yes|YES)$ ]] && INSTALL_REMOTE=1
      read -r -p "Installer Arrangement Builder ? (o/n) " choice
      [[ "$choice" =~ ^([oOyY]|oui|OUI|yes|YES)$ ]] && INSTALL_BUILDER=1
      read -r -p "Installer AutoScene ? (o/n) " choice
      [[ "$choice" =~ ^([oOyY]|oui|OUI|yes|YES)$ ]] && INSTALL_AUTOSCENE=1
      read -r -p "Installer CL MIDI Console ? (o/n) " choice
      [[ "$choice" =~ ^([oOyY]|oui|OUI|yes|YES)$ ]] && INSTALL_MIDI_CONSOLE=1
      ;;
    remote,builder|builder,remote)
      INSTALL_REMOTE=1; INSTALL_BUILDER=1 ;;
    remote,autoscene|autoscene,remote)
      INSTALL_REMOTE=1; INSTALL_AUTOSCENE=1 ;;
    builder,autoscene|autoscene,builder)
      INSTALL_BUILDER=1; INSTALL_AUTOSCENE=1 ;;
    *)
      normalized=",${COMPONENT_CHOICE},"
      [[ "$normalized" == *,remote,* ]] && INSTALL_REMOTE=1
      [[ "$normalized" == *,builder,* ]] && INSTALL_BUILDER=1
      [[ "$normalized" == *,autoscene,* ]] && INSTALL_AUTOSCENE=1
      [[ "$normalized" == *,midi-console,* ]] && INSTALL_MIDI_CONSOLE=1
      if [[ "$INSTALL_REMOTE$INSTALL_BUILDER$INSTALL_AUTOSCENE$INSTALL_MIDI_CONSOLE" == "0000" ]]; then
        echo "Installation annulée."
        exit 0
      fi
      ;;
  esac
fi

echo
echo "Vérification des composants…"
if [[ "$INSTALL_REMOTE" == "1" ]]; then
  require_source "$APPLICATIONS_SOURCE/CL Audio Controller.app"
  require_source "$LIVE_CURRENT_SOURCE/Remote Scripts/AbletonOSC"
  require_source "$LIVE_CURRENT_SOURCE/Max for Live/CL Audio Controller - Remote"
fi

mkdir -p "$USER_APPS" "$REMOTE_SCRIPTS" "$(dirname "$M4L_REMOTE_TARGET")"

if [[ "$INSTALL_REMOTE" == "1" ]]; then
  install_item "$APPLICATIONS_SOURCE/CL Audio Controller.app" \
    "$USER_APPS/CL Audio Controller.app" "Télécommande — CL Audio Controller" "remote"
  install_item "$LIVE_CURRENT_SOURCE/Remote Scripts/AbletonOSC" \
    "$REMOTE_SCRIPTS/AbletonOSC" "Télécommande — AbletonOSC CL" "remote"
  install_item "$LIVE_CURRENT_SOURCE/Max for Live/CL Audio Controller - Remote" \
    "$M4L_REMOTE_TARGET" \
    "Télécommande — LTC et X-Fader" "remote"
fi

if [[ "$INSTALL_BUILDER" == "1" ]]; then
  install_item "$APPLICATIONS_SOURCE/Arrangement Builder Live.app" \
    "$USER_APPS/Arrangement Builder Live.app" "Builder — Application" "builder"
  install_item "$LIVE_CURRENT_SOURCE/Remote Scripts/CL_Arrangement_Builder_Live" \
    "$REMOTE_SCRIPTS/CL_Arrangement_Builder_Live" \
    "Builder — Remote Script" "builder"
fi

if [[ "$INSTALL_AUTOSCENE" == "1" ]]; then
  install_item "$LIVE_CURRENT_SOURCE/Max for Live/Paradis Latin AutoScene" \
    "$M4L_AUTOSCENE_TARGET" \
    "AutoScene — Version Live 11/12" "autoscene"
fi

if [[ "$INSTALL_AUTOSCENE_LIVE10" == "1" ]]; then
  install_item "$LIVE10_SOURCE_ROOT/Max for Live/Paradis Latin AutoScene - Live 10" \
    "$M4L_LIVE10_TARGET" \
    "AutoScene — Version Live 10" "autoscene-live10"
fi

if [[ "$INSTALL_MIDI_CONSOLE" == "1" ]]; then
  install_item "$LIVE_CURRENT_SOURCE/Max for Live/CL MIDI Console Monitor" \
    "$M4L_MIDI_CONSOLE_TARGET" \
    "MIDI Console — Périphérique Max for Live" "midi-console"
  install_item "$MIDI_TOOLS_SOURCE" "$MIDI_TOOLS_TARGET" \
    "MIDI Console — Outils réseau" "midi-console"
  install_item "$APPLICATIONS_SOURCE/CL MIDI Network Assistant.app" \
    "$USER_APPS/CL MIDI Network Assistant.app" \
    "MIDI Console — Assistant réseau" "midi-console"
fi

write_install_manifest

echo
echo "============================================================"
echo " INSTALLATION TERMINÉE"
echo "============================================================"
echo "Applications : $USER_APPS"
echo "Remote Scripts : $REMOTE_SCRIPTS"
echo "Max for Live : $(dirname "$M4L_REMOTE_TARGET")"
echo "Manifeste : $INSTALL_MANIFEST"
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
