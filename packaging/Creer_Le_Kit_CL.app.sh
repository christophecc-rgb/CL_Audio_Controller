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
set picked to choose from list {"Installer directement sur ce Mac", "Bureau uniquement", "Bureau + iCloud Drive", "Bureau + AirDrop", "Bureau + iCloud Drive + AirDrop"} with title "Créer le Kit CL" with prompt "Que souhaitez-vous faire après la création et la vérification ?" default items {"Installer directement sur ce Mac"}
if picked is false then return ""
return item 1 of picked
APPLESCRIPT
)"
[[ -n "$export_choice" ]] || exit 0

install_local=0
[[ "$export_choice" == "Installer directement sur ce Mac" ]] && install_local=1

local_export_root=""
cleanup_local_export() {
  if [[ -n "$local_export_root" && -d "$local_export_root" ]]; then
    rm -rf "$local_export_root"
  fi
}
trap cleanup_local_export EXIT

use_icloud=0
use_airdrop=0
[[ "$export_choice" == *"iCloud Drive"* ]] && use_icloud=1
[[ "$export_choice" == *"AirDrop"* ]] && use_airdrop=1

/usr/bin/osascript -e 'display notification "La construction a démarré. Cette opération peut prendre quelques minutes." with title "Créer le Kit CL"'

quoted_builder="$(printf '%q' "$BUILDER")"
quoted_log="$(printf '%q' "$LOG_FILE")"
quoted_status="$(printf '%q' "$STATUS_FILE")"
terminal_command="/bin/bash $quoted_builder >$quoted_log 2>&1; result=\$?; printf '%s\\n' \"\$result\" >$quoted_status"
if [[ "$install_local" == "1" ]]; then
  local_export_root="$(mktemp -d "/private/tmp/CL_Suite_Export_Local_XXXXXX")"
  quoted_export_root="$(printf '%q' "$local_export_root")"
  terminal_command="CL_SUITE_EXPORT_DIR=$quoted_export_root CL_SUITE_SKIP_ICLOUD=1 CL_SUITE_REVEAL_OUTPUT=0 $terminal_command"
elif [[ "$use_icloud" != "1" ]]; then
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
  latest_zip="$(grep -E '^/.*/CL_Suite_Transport_[^/]+\.zip$' "$LOG_FILE" | tail -n 1 || true)"
  if [[ -n "$latest_zip" ]]; then
    if [[ "$install_local" != "1" ]]; then
      /usr/bin/open -R "$latest_zip" >/dev/null 2>&1 || true
    fi
    if [[ "$use_airdrop" == "1" ]]; then
      # Présenter la véritable feuille macOS « Partager via AirDrop » avec le
      # ZIP déjà joint. L'utilisateur n'a plus qu'à choisir le destinataire.
      if ! /usr/bin/osascript -l JavaScript - "$latest_zip" >/dev/null <<'JXA'
ObjC.import('AppKit');
ObjC.import('Foundation');
function run(argv) {
  const fileURL = $.NSURL.fileURLWithPath($(argv[0]));
  const service = $.NSSharingService.sharingServiceNamed($.NSSharingServiceNameSendViaAirDrop);
  if (!service) throw new Error('Service AirDrop indisponible');
  service.performWithItems([fileURL]);
  delay(2);
}
JXA
      then
        show_error "Le kit est prêt, mais la fenêtre de partage AirDrop n’a pas pu être ouverte. Le ZIP reste disponible sur le Bureau."
      fi
    fi
    destinations="Bureau"
    [[ "$use_icloud" == "1" ]] && destinations="$destinations + iCloud Drive"
    [[ "$use_airdrop" == "1" ]] && destinations="$destinations + AirDrop ouvert"
    if [[ "$install_local" == "1" ]]; then
      local_install_root="$(mktemp -d "/private/tmp/CL_Suite_Installation_Locale_XXXXXX")"
      /usr/bin/ditto -x -k "$latest_zip" "$local_install_root"
      installer_app="$(find "$local_install_root" -maxdepth 3 -type d -name "Installer la Suite CL.app" -print -quit)"
      if [[ -z "$installer_app" ]]; then
        show_error "Le kit est créé, mais son installateur local est introuvable. Consultez $LOG_FILE"
        exit 1
      fi
      /usr/bin/open -W "$installer_app"
      rm -rf "$local_install_root"
      /usr/bin/osascript -e 'display dialog "Installation locale terminée. Les composants choisis ont été placés dans les emplacements prévus pour macOS et Ableton Live." buttons {"OK"} default button "OK" with title "Suite CL installée" with icon note'
      exit 0
    else
      install_result=""
    fi
    /usr/bin/osascript -e "display dialog \"Kit créé et vérifié.\n\nExport : $destinations$install_result\n\n$latest_zip\" buttons {\"OK\"} default button \"OK\" with title \"Kit CL prêt\" with icon note"
  else
    show_error "La construction est terminée, mais le kit validé n’a pas été retrouvé. Consultez $LOG_FILE"
    exit 1
  fi
else
  show_error "La construction a échoué. Le rapport est disponible dans $LOG_FILE"
  /usr/bin/open -R "$LOG_FILE" >/dev/null 2>&1 || true
  exit 1
fi
