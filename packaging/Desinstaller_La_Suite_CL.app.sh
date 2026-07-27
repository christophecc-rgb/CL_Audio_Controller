#!/bin/bash
set -euo pipefail

RESOURCES="$(cd "$(dirname "$0")/../Resources" && pwd)"
ENGINE="$RESOURCES/Desinstaller_La_Suite_CL.command"
LOG_FILE="/private/tmp/CL_Suite_Desinstallateur.log"

[[ -x "$ENGINE" ]] || exit 1

selected="$(/usr/bin/osascript <<'APPLESCRIPT'
set picked to choose from list {"CL Audio Controller", "CL Arrangement Builder Live", "Paradis Latin AutoScene (Live 11/12)", "Paradis Latin AutoScene (Live 10)", "CL MIDI Console Monitor"} with title "Désinstaller la Suite CL" with prompt "Sélectionnez les composants à retirer :" with multiple selections allowed
if picked is false then return ""
return picked as text
APPLESCRIPT
)"
[[ -n "$selected" ]] || exit 0

components=""
[[ "$selected" == *"CL Audio Controller"* ]] && components="remote"
[[ "$selected" == *"CL Arrangement Builder Live"* ]] && components="${components:+$components,}builder"
[[ "$selected" == *"Paradis Latin AutoScene (Live 11/12)"* ]] && components="${components:+$components,}autoscene"
[[ "$selected" == *"Paradis Latin AutoScene (Live 10)"* ]] && components="${components:+$components,}autoscene-live10"
[[ "$selected" == *"CL MIDI Console Monitor"* ]] && components="${components:+$components,}midi-console"

confirmation="$(/usr/bin/osascript -e 'display dialog "Les éléments sélectionnés seront déplacés dans la Corbeille et resteront récupérables." buttons {"Annuler", "Désinstaller"} default button "Annuler" with title "Désinstaller la Suite CL" with icon caution' -e 'button returned of result')"
[[ "$confirmation" == "Désinstaller" ]] || exit 0

if CL_SUITE_NONINTERACTIVE=1 CL_SUITE_UNINSTALL_COMPONENTS="$components" "$ENGINE" >"$LOG_FILE" 2>&1; then
  /usr/bin/osascript -e 'display dialog "Désinstallation terminée. Les éléments retirés restent récupérables dans la Corbeille." buttons {"OK"} default button "OK" with title "Suite CL" with icon note'
else
  /usr/bin/osascript -e "display dialog \"La désinstallation a échoué. Consultez $LOG_FILE\" buttons {\"Fermer\"} default button \"Fermer\" with title \"Suite CL\" with icon stop"
  exit 1
fi
