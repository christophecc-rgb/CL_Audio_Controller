#!/bin/bash
set -euo pipefail

RESOURCES="$(cd "$(dirname "$0")/../Resources" && pwd)"
TOOLS="$RESOURCES/Network Tools"
LOG_FILE="/private/tmp/CL_MIDI_Network_Assistant.log"

report_error() {
  local line="$1"
  local status="$2"
  local message="Échec de CL MIDI Network Assistant (ligne $line, code $status). Consultez $LOG_FILE"
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >>"$LOG_FILE"
  osascript -e 'on run argv' \
    -e 'display dialog (item 1 of argv) with title "CL MIDI Network Assistant" buttons {"OK"} default button "OK" with icon stop' \
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
  -e 'set picked to choose from list {"Ouvrir les réglages MIDI réseau", "Tester un aller-retour", "Lancer le simulateur Yamaha", "Reconnecter une session RTP"} with title "CL MIDI Network Assistant" with prompt "Choisissez une opération"' \
  -e 'if picked is false then return ""' \
  -e 'return item 1 of picked')"
printf '%s CHOICE=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$choice" >>"$LOG_FILE"

case "$choice" in
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
