#!/bin/bash
set -euo pipefail

RESOURCES="$(cd "$(dirname "$0")/../Resources" && pwd)"
TOOLS="$RESOURCES/Network Tools"
LOG_FILE="/private/tmp/CL_MIDI_Network_Assistant.log"

report_error() {
  local line="$1"
  local status="$2"
  local message="Échec de CL MIDI Network Manager (ligne $line, code $status). Consultez $LOG_FILE"
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >>"$LOG_FILE"
  osascript -e 'on run argv' \
    -e 'display dialog (item 1 of argv) with title "CL MIDI Network Manager" buttons {"OK"} default button "OK" with icon stop' \
    -e 'end run' \
    "$message" >/dev/null 2>&1 || true
}

trap 'status=$?; report_error "$LINENO" "$status"' ERR
printf '%s START executable=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$0" >>"$LOG_FILE"

open_terminal_command() {
  local command="$1"
  osascript \
    -e 'on run argv' \
    -e 'tell application "Terminal" to do script (item 1 of argv)' \
    -e 'end run' \
    "$command"
}

choice="$(osascript \
  -e 'set picked to choose from list {"Vérifier MIDI / MTC", "Ouvrir les réglages MIDI réseau", "Tester un aller-retour", "Lancer le simulateur Yamaha", "Reconnecter une session RTP"} with title "CL MIDI Network Manager" with prompt "Choisissez une opération"' \
  -e 'if picked is false then return ""' \
  -e 'return item 1 of picked')"
printf '%s CHOICE=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$choice" >>"$LOG_FILE"

case "$choice" in
  "Vérifier MIDI / MTC")
    midi_dump="$(/usr/sbin/system_profiler SPMIDIDataType 2>/dev/null || true)"

    contains_any() {
      local candidate
      for candidate in "$@"; do
        if printf '%s\n' "$midi_dump" | /usr/bin/grep -Fqi -- "$candidate"; then
          return 0
        fi
      done
      return 1
    }

    report="CL MIDI / MTC — CONTRÔLE NON DESTRUCTIF
"

    missing_iac=0

    if contains_any \
      "CL Ableton Clock IAC" \
      "Gestionnaire IAC CL Ableton Clock IAC" \
      "IAC Driver CL Ableton Clock IAC" \
      "Gestionnaire IAC Ableton Clock" \
      "IAC Driver Ableton Clock"; then
      report="${report}
✓ CL Ableton Clock IAC"
    else
      report="${report}
✗ CL Ableton Clock IAC — À CRÉER"
      missing_iac=1
    fi

    if contains_any \
      "CL MTC IAC" \
      "Gestionnaire IAC CL MTC IAC" \
      "IAC Driver CL MTC IAC" \
      "Gestionnaire IAC MTC vers Logic" \
      "IAC Driver MTC vers Logic"; then
      report="${report}
✓ CL MTC IAC"
    else
      report="${report}
✗ CL MTC IAC — À CRÉER"
      missing_iac=1
    fi

    if contains_any \
      "CL Show Control IAC" \
      "Gestionnaire IAC CL Show Control IAC" \
      "IAC Driver CL Show Control IAC" \
      "Gestionnaire IAC Bus 1" \
      "IAC Driver Bus 1"; then
      report="${report}
✓ CL Show Control IAC"
    else
      report="${report}
✗ CL Show Control IAC — À CRÉER"
      missing_iac=1
    fi

    if contains_any "CL MIDI Return Test"; then
      report="${report}
✓ CL MIDI Return Test"
    else
      report="${report}
○ CL MIDI Return Test absent
  Créé par les outils CL — NE PAS créer un bus IAC homonyme"
    fi

    if contains_any \
      "CL Show Control RTP" \
      "Réseau CL Show Control RTP" \
      "Network CL Show Control RTP"; then
      report="${report}
✓ CL Show Control RTP détecté"
    else
      report="${report}
○ CL Show Control RTP non détecté"
    fi

    if contains_any \
      "CL Console Return RTP" \
      "Réseau CL Console Return RTP" \
      "Network CL Console Return RTP" \
      "Réseau RTP MB Chris" \
      "Network RTP MB Chris"; then
      report="${report}
✓ CL Console Return RTP détecté"
    else
      report="${report}
○ CL Console Return RTP non détecté"
    fi

    bridge="$HOME/Applications/CL Show Control.app/Contents/Frameworks/tools/ableton_mtc_bridge/CLAbletonMTCBridge"
    if [[ -x "$bridge" ]]; then
      report="${report}
✓ CLAbletonMTCBridge présent"
    else
      report="${report}
✗ CLAbletonMTCBridge absent"
    fi

    report="${report}

Référence MTC :
• 25 fps
• UDP absolu : 20809
• UDP diagnostic : 20810
• CL5 : canal MIDI 1
• QL1 : canal MIDI 2

Aucun port, nom, IP ou routage n'a été modifié."

    printf '%s CHECK MIDI_MTC missing_iac=%s\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "$missing_iac" >>"$LOG_FILE"

    result="$(/usr/bin/osascript - "$report" <<'APPLESCRIPT'
on run argv
    set messageText to item 1 of argv
    set answer to display dialog messageText ¬
        with title "CL MIDI / MTC" ¬
        buttons {"Fermer", "Configuration Audio et MIDI"} ¬
        default button "Fermer" ¬
        with icon note
    return button returned of answer
end run
APPLESCRIPT
)"

    if [[ "$result" == "Configuration Audio et MIDI" ]]; then
      open -a "Audio MIDI Setup"
    fi
    ;;

  "Ouvrir les réglages MIDI réseau")
    open -a "Audio MIDI Setup"
    ;;
  "Tester un aller-retour")
    endpoint="$(osascript -e 'text returned of (display dialog "Nom du port RTP MIDI" default answer "Session RTP 1")')"
    program="$(osascript -e 'text returned of (display dialog "Numéro de scène témoin" default answer "42")')"
    command="$(printf '%q ' "$TOOLS/CLMIDIRoundTripTester" --endpoint "$endpoint" --program "$program" --timeout 5)"
    open_terminal_command "$command; echo; read -n 1 -s -r -p 'Appuyez sur une touche pour fermer'"
    ;;
  "Lancer le simulateur Yamaha")
    endpoint="$(osascript -e 'text returned of (display dialog "Nom de la session RTP du Mac simulateur" default answer "QL1 simulator")')"
    command="$(printf '%q ' "$TOOLS/CLYamahaConsoleSimulator" --label QL1 --delay-ms 80 --endpoint "$endpoint")"
    printf '%s LAUNCH simulator endpoint=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$endpoint" >>"$LOG_FILE"
    open_terminal_command "$command"
    ;;
  "Reconnecter une session RTP")
    peer="$(osascript -e 'text returned of (display dialog "Nom de la session RTP distante" default answer "MB Pro")')"
    host="$(osascript -e 'text returned of (display dialog "Adresse IP facultative (laisser vide pour Bonjour)" default answer "")')"
    if [[ -n "$host" ]]; then
      port="$(osascript -e 'text returned of (display dialog "Port RTP MIDI" default answer "5004")')"
      command="$(printf '%q ' "$TOOLS/CLMIDINetworkGuardian" --peer-name "$peer" --peer-host "$host" --peer-port "$port")"
    else
      command="$(printf '%q ' "$TOOLS/CLMIDINetworkGuardian" --peer-name "$peer")"
    fi
    printf '%s LAUNCH guardian peer=%s host=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$peer" "${host:-Bonjour}" >>"$LOG_FILE"
    open_terminal_command "$command"
    ;;
  *) exit 0 ;;
esac
