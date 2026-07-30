#!/bin/bash
set -euo pipefail

INSTALL_HOME="${CL_SUITE_INSTALL_HOME:-$HOME}"
SUPPORT_DIR="$INSTALL_HOME/Library/Application Support/CL Audio Controller"
INSTALL_MANIFEST="$SUPPORT_DIR/CL_Suite_install_manifest.tsv"
TRASH_ROOT="${CL_SUITE_TRASH_DIR:-$INSTALL_HOME/.Trash}"
STAMP="$(date '+%Y-%m-%d_%H%M%S')"
TRASH_SESSION="$TRASH_ROOT/CL Suite désinstallée $STAMP"

fail() {
  echo
  echo "ERREUR : $1" >&2
  exit 1
}

[[ ! -L "$INSTALL_MANIFEST" ]] || fail "le manifeste est un lien symbolique : $INSTALL_MANIFEST"
[[ -f "$INSTALL_MANIFEST" ]] || fail "aucun manifeste d'installation trouvé. Rien n'a été retiré. Réinstallez d'abord la suite avec le nouvel installateur."

UNINSTALL_REMOTE=0
UNINSTALL_CONTROLLER=0
UNINSTALL_ABLETON_READER=0
UNINSTALL_BUILDER=0
UNINSTALL_AUTOSCENE=0
UNINSTALL_LIVE10=0
UNINSTALL_MIDI_CONSOLE=0
UNINSTALL_MIDI_RECEIVER=0

CHOICE="${CL_SUITE_UNINSTALL_COMPONENTS:-}"
if [[ -z "$CHOICE" ]]; then
  echo "============================================================"
  echo " DÉSINSTALLER LA SUITE CL"
  echo "============================================================"
  echo
  echo "Les éléments seront déplacés dans la Corbeille, jamais effacés."
  echo "Les Live Sets, projets Ableton et sauvegardes ne seront pas touchés."
  echo
  echo "  1 — Toute la suite"
  echo "  2 — Télécommande CL Audio"
  echo "  3 — Arrangement Builder"
  echo "  4 — AutoScene Live 11/12"
  echo "  5 — AutoScene Live 10"
  echo "  6 — CL MIDI Console"
  echo "  7 — Choix personnalisé"
  echo "  8 — Annuler"
  read -r -p "Votre choix : " CHOICE
fi

case "$CHOICE" in
  1|all|complete)
    UNINSTALL_REMOTE=1; UNINSTALL_BUILDER=1; UNINSTALL_AUTOSCENE=1; UNINSTALL_LIVE10=1; UNINSTALL_MIDI_CONSOLE=1; UNINSTALL_MIDI_RECEIVER=1 ;;
  2|remote) UNINSTALL_REMOTE=1 ;;
  3|builder) UNINSTALL_BUILDER=1 ;;
  4|autoscene) UNINSTALL_AUTOSCENE=1 ;;
  5|autoscene-live10|live10) UNINSTALL_LIVE10=1 ;;
  6|midi-console) UNINSTALL_MIDI_CONSOLE=1 ;;
  controller|show-control) UNINSTALL_CONTROLLER=1 ;;
  ableton-reader|reader) UNINSTALL_ABLETON_READER=1 ;;
  midi-receiver|receiver|simulator) UNINSTALL_MIDI_RECEIVER=1 ;;
  7|custom)
    read -r -p "Retirer la Télécommande CL Audio ? (o/n) " answer
    [[ "$answer" =~ ^([oOyY]|oui|OUI|yes|YES)$ ]] && UNINSTALL_REMOTE=1
    read -r -p "Retirer Arrangement Builder ? (o/n) " answer
    [[ "$answer" =~ ^([oOyY]|oui|OUI|yes|YES)$ ]] && UNINSTALL_BUILDER=1
    read -r -p "Retirer AutoScene Live 11/12 ? (o/n) " answer
    [[ "$answer" =~ ^([oOyY]|oui|OUI|yes|YES)$ ]] && UNINSTALL_AUTOSCENE=1
    read -r -p "Retirer AutoScene Live 10 ? (o/n) " answer
    [[ "$answer" =~ ^([oOyY]|oui|OUI|yes|YES)$ ]] && UNINSTALL_LIVE10=1
    read -r -p "Retirer CL MIDI Console ? (o/n) " answer
    [[ "$answer" =~ ^([oOyY]|oui|OUI|yes|YES)$ ]] && UNINSTALL_MIDI_CONSOLE=1
    ;;
  *)
    normalized=",${CHOICE},"
    [[ "$normalized" == *,remote,* ]] && UNINSTALL_REMOTE=1
    [[ "$normalized" == *,controller,* ]] && UNINSTALL_CONTROLLER=1
    [[ "$normalized" == *,ableton-reader,* ]] && UNINSTALL_ABLETON_READER=1
    [[ "$normalized" == *,builder,* ]] && UNINSTALL_BUILDER=1
    [[ "$normalized" == *,autoscene,* ]] && UNINSTALL_AUTOSCENE=1
    [[ "$normalized" == *,autoscene-live10,* ]] && UNINSTALL_LIVE10=1
    [[ "$normalized" == *,midi-console,* ]] && UNINSTALL_MIDI_CONSOLE=1
    [[ "$normalized" == *,midi-receiver,* ]] && UNINSTALL_MIDI_RECEIVER=1
    [[ "$normalized" == *,simulator,* ]] && UNINSTALL_MIDI_RECEIVER=1
    if [[ "$UNINSTALL_REMOTE$UNINSTALL_CONTROLLER$UNINSTALL_ABLETON_READER$UNINSTALL_BUILDER$UNINSTALL_AUTOSCENE$UNINSTALL_LIVE10$UNINSTALL_MIDI_CONSOLE$UNINSTALL_MIDI_RECEIVER" == "00000000" ]]; then
      echo "Désinstallation annulée."
      exit 0
    fi
    ;;
esac

is_selected() {
  case "$1" in
    remote) [[ "$UNINSTALL_REMOTE" == "1" ]] ;;
    controller) [[ "$UNINSTALL_REMOTE" == "1" || "$UNINSTALL_CONTROLLER" == "1" ]] ;;
    ableton-reader) [[ "$UNINSTALL_REMOTE" == "1" || "$UNINSTALL_ABLETON_READER" == "1" ]] ;;
    builder) [[ "$UNINSTALL_BUILDER" == "1" ]] ;;
    autoscene) [[ "$UNINSTALL_AUTOSCENE" == "1" ]] ;;
    autoscene-live10) [[ "$UNINSTALL_LIVE10" == "1" ]] ;;
    midi-console) [[ "$UNINSTALL_MIDI_CONSOLE" == "1" ]] ;;
    midi-receiver) [[ "$UNINSTALL_MIDI_RECEIVER" == "1" ]] ;;
    *) return 1 ;;
  esac
}

is_allowed_target() {
  case "$1" in
    "$INSTALL_HOME/Applications/CL Audio Controller.app"|\
    "$INSTALL_HOME/Applications/Arrangement Builder Live.app"|\
    "$INSTALL_HOME/Music/Ableton/User Library/Remote Scripts/AbletonOSC"|\
    "$INSTALL_HOME/Music/Ableton/User Library/Remote Scripts/CL_Arrangement_Builder_Live"|\
    "$INSTALL_HOME/Music/Ableton/User Library/Presets/Audio Effects/Max Audio Effect/CL Audio Controller - Remote"|\
    "$INSTALL_HOME/Music/Ableton/User Library/Presets/Audio Effects/Max Audio Effect/CL Audio Controller - AutoScene"|\
    "$INSTALL_HOME/Music/Ableton/User Library/Presets/Audio Effects/Max Audio Effect/CL Audio Controller - Live 10"|\
    "$INSTALL_HOME/Music/Ableton/User Library/Presets/MIDI Effects/Max MIDI Effect/CL MIDI Console Monitor"|\
    "$INSTALL_HOME/Library/Application Support/CL MIDI Console/Network Tools"|\
    "$INSTALL_HOME/Applications/CL MIDI Network Assistant.app"|\
    "$INSTALL_HOME/Applications/CL MIDI RTP Agent.app"|\
    "$INSTALL_HOME/Applications/CL MIDI RTP Simulator.app"|\
    "$INSTALL_HOME/Applications/CL MIDI RTP Receiver.app") return 0 ;;
    *) return 1 ;;
  esac
}

SELECTED_FILE="$(mktemp "/private/tmp/CL_Suite_Uninstall_XXXXXX")"
REMAINING_FILE="${SELECTED_FILE}.remaining"
trap 'rm -f "$SELECTED_FILE" "$REMAINING_FILE"' EXIT

while IFS=$'\t' read -r component target installed_at; do
  [[ -n "$component" && -n "$target" && -n "$installed_at" ]] || continue
  if is_selected "$component"; then
    is_allowed_target "$target" || fail "cible non autorisée dans le manifeste : $target"
    printf '%s\t%s\t%s\n' "$component" "$target" "$installed_at" >> "$SELECTED_FILE"
  else
    printf '%s\t%s\t%s\n' "$component" "$target" "$installed_at" >> "$REMAINING_FILE"
  fi
done < "$INSTALL_MANIFEST"

[[ -s "$SELECTED_FILE" ]] || fail "aucun élément sélectionné n'est attesté par le manifeste. Rien n'a été retiré."

echo
echo "Éléments qui seront déplacés dans la Corbeille :"
while IFS=$'\t' read -r component target installed_at; do
  if [[ -e "$target" || -L "$target" ]]; then
    echo "  • $target"
  else
    echo "  • $target (déjà absent)"
  fi
done < "$SELECTED_FILE"

if [[ "${CL_SUITE_NONINTERACTIVE:-0}" != "1" ]]; then
  echo
  read -r -p "Confirmer la désinstallation ? Tapez DESINSTALLER : " confirmation
  [[ "$confirmation" == "DESINSTALLER" ]] || { echo "Désinstallation annulée."; exit 0; }
fi

if [[ "$UNINSTALL_MIDI_CONSOLE" == "1" && "$INSTALL_HOME" == "$HOME" && "${CL_SUITE_SKIP_POSTINSTALL:-0}" != "1" ]]; then
  /usr/bin/osascript >/dev/null 2>&1 <<'APPLESCRIPT' || true
tell application "System Events"
  if exists login item "CL MIDI Network Assistant" then
    delete login item "CL MIDI Network Assistant"
  end if
end tell
APPLESCRIPT
  echo "Démarrage automatique de CL MIDI Network Assistant retiré."
fi
if [[ "$UNINSTALL_ABLETON_READER" == "1" && "$INSTALL_HOME" == "$HOME" && "${CL_SUITE_SKIP_POSTINSTALL:-0}" != "1" ]]; then
  /usr/bin/osascript >/dev/null 2>&1 <<'APPLESCRIPT' || true
tell application "System Events"
  if exists login item "CL MIDI RTP Agent" then delete login item "CL MIDI RTP Agent"
end tell
APPLESCRIPT
fi
if [[ "$UNINSTALL_MIDI_RECEIVER" == "1" && "$INSTALL_HOME" == "$HOME" && "${CL_SUITE_SKIP_POSTINSTALL:-0}" != "1" ]]; then
  /usr/bin/osascript >/dev/null 2>&1 <<'APPLESCRIPT' || true
tell application "System Events"
  if exists login item "CL MIDI RTP Simulator" then delete login item "CL MIDI RTP Simulator"
end tell
APPLESCRIPT
fi

mkdir -p "$TRASH_SESSION"
REPORT="$TRASH_SESSION/RAPPORT_DESINSTALLATION.txt"
printf 'Désinstallation CL Suite — %s\n\n' "$STAMP" > "$REPORT"

while IFS=$'\t' read -r component target installed_at; do
  if [[ -e "$target" || -L "$target" ]]; then
    destination="$TRASH_SESSION/$component/$(basename "$target")"
    mkdir -p "$(dirname "$destination")"
    [[ ! -e "$destination" ]] || fail "collision dans la Corbeille : $destination"
    mv "$target" "$destination"
    printf 'Déplacé : %s\nVers : %s\n\n' "$target" "$destination" >> "$REPORT"
  else
    printf 'Déjà absent : %s\n\n' "$target" >> "$REPORT"
  fi
done < "$SELECTED_FILE"

if [[ -s "$REMAINING_FILE" ]]; then
  cp "$REMAINING_FILE" "$INSTALL_MANIFEST.tmp"
  chmod 600 "$INSTALL_MANIFEST.tmp"
  mv "$INSTALL_MANIFEST.tmp" "$INSTALL_MANIFEST"
else
  mv "$INSTALL_MANIFEST" "$TRASH_SESSION/CL_Suite_install_manifest.tsv"
fi

echo
echo "============================================================"
echo " DÉSINSTALLATION TERMINÉE"
echo "============================================================"
echo "Éléments récupérables dans :"
echo "$TRASH_SESSION"
echo
echo "Rapport : $REPORT"

if [[ "${CL_SUITE_NONINTERACTIVE:-0}" != "1" ]]; then
  open -R "$TRASH_SESSION" >/dev/null 2>&1 || true
  read -r -p "Appuyez sur Entrée pour fermer cette fenêtre." _
fi
