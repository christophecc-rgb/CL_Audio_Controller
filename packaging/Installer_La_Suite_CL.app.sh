#!/bin/bash
set -euo pipefail

RESOURCES="$(cd "$(dirname "$0")/../Resources" && pwd)"
ENGINE="$RESOURCES/Installer_Toute_La_Suite_CL.command"
LOG_FILE="/private/tmp/CL_Suite_Installer.log"

show_error() {
  /usr/bin/osascript \
    -e 'on run argv' \
    -e 'display dialog (item 1 of argv) buttons {"Fermer"} default button "Fermer" with title "Installer la Suite CL" with icon stop' \
    -e 'end run' \
    -- "$1"
}

[[ -x "$ENGINE" ]] || {
  show_error "Le moteur d’installation est absent du kit."
  exit 1
}

live_choice="Ableton Live 12"
live_family="12"

selected="$(/usr/bin/osascript \
  -e 'set picked to choose from list {"CL Show Control", "CL Arrangement Builder", "Paradis Latin AutoScene", "CL MIDI Console Monitor"} with title "Installer la Suite CL" with prompt "Sélectionnez les composants à installer :" default items {"CL Show Control", "CL Arrangement Builder", "Paradis Latin AutoScene", "CL MIDI Console Monitor"} with multiple selections allowed' \
  -e 'if picked is false then return ""' \
  -e 'set AppleScript'\''s text item delimiters to "|"' \
  -e 'return picked as text'
)"

[[ -n "$selected" ]] || exit 0

components=""
[[ "$selected" == *"CL Show Control"* ]] && components="${components:+$components,}controller"
[[ "$selected" == *"CL Arrangement Builder"* ]] && components="${components:+$components,}builder"
[[ "$selected" == *"Paradis Latin AutoScene"* ]] && components="${components:+$components,}autoscene"
[[ "$selected" == *"CL MIDI Console Monitor"* ]] && components="${components:+$components,}midi-console"

summary="Version : $live_choice
Composants : $components"

confirmation="$(/usr/bin/osascript \
  -e 'on run argv' \
  -e 'set r to display dialog (item 1 of argv) buttons {"Annuler", "Installer"} default button "Installer" with title "Installer la Suite CL"' \
  -e 'return button returned of r' \
  -e 'end run' \
  -- "$summary"
)"

[[ "$confirmation" == "Installer" ]] || exit 0

if CL_SUITE_NONINTERACTIVE=1 \
   CL_SUITE_LIVE_FAMILY="$live_family" \
   CL_SUITE_COMPONENTS="$components" \
   "$ENGINE" >"$LOG_FILE" 2>&1; then

  /usr/bin/osascript \
    -e 'display dialog "Installation terminée. Fermez complètement Ableton Live si celui-ci était ouvert, puis relancez-le." buttons {"OK"} default button "OK" with title "Suite CL installée" with icon note'
else
  show_error "L’installation a échoué. Le rapport est disponible dans $LOG_FILE"
  /usr/bin/open -R "$LOG_FILE" >/dev/null 2>&1 || true
  exit 1
fi
