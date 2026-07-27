#!/bin/bash
set -euo pipefail

RESOURCES="$(cd "$(dirname "$0")/../Resources" && pwd)"
ENGINE="$RESOURCES/Installer_Toute_La_Suite_CL.command"
LOG_FILE="/private/tmp/CL_Suite_Installer.log"

show_error() {
  /usr/bin/osascript -e "display dialog \"$1\" buttons {\"Fermer\"} default button \"Fermer\" with title \"Installer la Suite CL\" with icon stop"
}

[[ -x "$ENGINE" ]] || { show_error "Le moteur d’installation est absent du kit."; exit 1; }

live_choice="$(/usr/bin/osascript <<'APPLESCRIPT'
set picked to choose from list {"Ableton Live 12 (recommandé)", "Ableton Live 10 — AutoScene uniquement"} with title "Installer la Suite CL" with prompt "Quelle version d’Ableton Live utilisez-vous ?" default items {"Ableton Live 12 (recommandé)"}
if picked is false then return ""
return item 1 of picked
APPLESCRIPT
)"
[[ -n "$live_choice" ]] || exit 0

if [[ "$live_choice" == "Ableton Live 10 — AutoScene uniquement" ]]; then
  live_family="10"
  components="autoscene-live10"
else
  live_family="12"
  selected="$(/usr/bin/osascript <<'APPLESCRIPT'
set picked to choose from list {"CL Audio Controller", "CL Arrangement Builder Live", "Paradis Latin AutoScene", "CL MIDI Console Monitor"} with title "Installer la Suite CL" with prompt "Sélectionnez les composants à installer :" default items {"CL Audio Controller", "CL Arrangement Builder Live", "Paradis Latin AutoScene", "CL MIDI Console Monitor"} with multiple selections allowed
if picked is false then return ""
return picked as text
APPLESCRIPT
)"
  [[ -n "$selected" ]] || exit 0
  components=""
  [[ "$selected" == *"CL Audio Controller"* ]] && components="remote"
  [[ "$selected" == *"CL Arrangement Builder Live"* ]] && components="${components:+$components,}builder"
  [[ "$selected" == *"Paradis Latin AutoScene"* ]] && components="${components:+$components,}autoscene"
  [[ "$selected" == *"CL MIDI Console Monitor"* ]] && components="${components:+$components,}midi-console"
fi

summary="Version : $live_choice\nComposants : $components"
confirmation="$(/usr/bin/osascript -e "display dialog \"$summary\" buttons {\"Annuler\", \"Installer\"} default button \"Installer\" with title \"Installer la Suite CL\"" -e 'button returned of result')"
[[ "$confirmation" == "Installer" ]] || exit 0

if CL_SUITE_NONINTERACTIVE=1 CL_SUITE_LIVE_FAMILY="$live_family" CL_SUITE_COMPONENTS="$components" "$ENGINE" >"$LOG_FILE" 2>&1; then
  /usr/bin/osascript <<'APPLESCRIPT'
display dialog "Installation terminée. Fermez complètement Ableton Live si celui-ci était ouvert, puis relancez-le." buttons {"OK"} default button "OK" with title "Suite CL installée" with icon note
APPLESCRIPT
else
  show_error "L’installation a échoué. Le rapport est disponible dans $LOG_FILE"
  /usr/bin/open -R "$LOG_FILE" >/dev/null 2>&1 || true
  exit 1
fi
