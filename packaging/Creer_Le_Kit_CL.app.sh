#!/bin/bash
set -euo pipefail

RESOURCES="$(cd "$(dirname "$0")/../Resources" && pwd)"
PROJECT_ROOT="$(cat "$RESOURCES/PROJECT_ROOT.txt")"
BUILDER="$PROJECT_ROOT/scripts/export_transport_kit.command"
LOG_FILE="/private/tmp/CL_Suite_Creation_$(date '+%Y-%m-%d_%H%M%S').log"
STATUS_FILE="${LOG_FILE%.log}.status"

show_error() {
  /usr/bin/osascript -e "display dialog \"$1\" buttons {\"Fermer\"} default button \"Fermer\" with title \"Créer le Kit CL\" with icon stop"
}

if [[ ! -x "$BUILDER" ]]; then
  show_error "Le projet CL Audio Controller est introuvable. Chemin attendu : $PROJECT_ROOT"
  exit 1
fi

confirmation="$(/usr/bin/osascript -e 'display dialog "Le kit complet va être reconstruit depuis les sources actuelles et contrôlé. Vous choisirez ensuite son mode d’export." buttons {"Annuler", "Créer le kit"} default button "Créer le kit" with title "Créer le Kit CL" with icon note' -e 'button returned of result')"
[[ "$confirmation" == "Créer le kit" ]] || exit 0

export_choice="$(/usr/bin/osascript <<'APPLESCRIPT'
set picked to choose from list {"Bureau uniquement", "Bureau + iCloud Drive", "Bureau + AirDrop", "Bureau + iCloud Drive + AirDrop"} with title "Créer le Kit CL" with prompt "Où souhaitez-vous exporter le kit après sa création ?" default items {"Bureau + iCloud Drive"}
if picked is false then return ""
return item 1 of picked
APPLESCRIPT
)"
[[ -n "$export_choice" ]] || exit 0

use_icloud=0
use_airdrop=0
[[ "$export_choice" == *"iCloud Drive"* ]] && use_icloud=1
[[ "$export_choice" == *"AirDrop"* ]] && use_airdrop=1

/usr/bin/osascript -e 'display notification "La construction a démarré. Cette opération peut prendre quelques minutes." with title "Créer le Kit CL"'

quoted_builder="$(printf '%q' "$BUILDER")"
quoted_log="$(printf '%q' "$LOG_FILE")"
quoted_status="$(printf '%q' "$STATUS_FILE")"
terminal_command="/bin/bash $quoted_builder >$quoted_log 2>&1; result=\$?; printf '%s\\n' \"\$result\" >$quoted_status"
if [[ "$use_icloud" != "1" ]]; then
  terminal_command="CL_SUITE_SKIP_ICLOUD=1 $terminal_command"
fi

rm -f "$STATUS_FILE"
/usr/bin/osascript - "$terminal_command" <<'APPLESCRIPT'
on run argv
  set shellCommand to item 1 of argv
  tell application "Terminal"
    activate
    do script shellCommand
  end tell
end run
APPLESCRIPT

while [[ ! -f "$STATUS_FILE" ]]; do
  sleep 1
done
build_status="$(tr -dc '0-9' <"$STATUS_FILE")"
rm -f "$STATUS_FILE"

if [[ "$build_status" == "0" ]]; then
  latest_zip="$(grep -E '^/.*/Desktop/CL_Suite_Transport_[^/]+\.zip$' "$LOG_FILE" | tail -n 1 || true)"
  if [[ -n "$latest_zip" ]]; then
    /usr/bin/open -R "$latest_zip" >/dev/null 2>&1 || true
    if [[ "$use_airdrop" == "1" ]]; then
      /usr/bin/open "airdrop://" >/dev/null 2>&1 || true
    fi
    destinations="Bureau"
    [[ "$use_icloud" == "1" ]] && destinations="$destinations + iCloud Drive"
    [[ "$use_airdrop" == "1" ]] && destinations="$destinations + AirDrop ouvert"
    /usr/bin/osascript -e "display dialog \"Kit créé et vérifié.\n\nExport : $destinations\n\n$latest_zip\" buttons {\"OK\"} default button \"OK\" with title \"Kit CL prêt\" with icon note"
  else
    show_error "La construction est terminée, mais le ZIP n’a pas été retrouvé sur le Bureau. Consultez $LOG_FILE"
    exit 1
  fi
else
  show_error "La construction a échoué. Le rapport est disponible dans $LOG_FILE"
  /usr/bin/open -R "$LOG_FILE" >/dev/null 2>&1 || true
  exit 1
fi
