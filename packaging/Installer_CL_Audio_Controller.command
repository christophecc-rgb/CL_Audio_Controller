#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PRIMARY_SOURCE="$SCRIPT_DIR/01 — Applications principales"
PROD_SOURCE="$SCRIPT_DIR/02 — Production"
MIDI_SOURCE="$SCRIPT_DIR/03 — MIDI & Réseau"
ABLETON_SOURCE="$SCRIPT_DIR/04 — Ableton & Max for Live"

USER_APPS="$HOME/Applications"
PROD_APPS="$USER_APPS/Prod Ableton"
MIDI_APPS="$USER_APPS/Analyse - Réseau - MIDI"

REMOTE_SCRIPTS="$HOME/Music/Ableton/User Library/Remote Scripts"

ABLETONOSC_SOURCE="$ABLETON_SOURCE/AbletonOSC CL/AbletonOSC"
ABLETONOSC_TARGET="$REMOTE_SCRIPTS/AbletonOSC"

BUILDER_REMOTE_SOURCE="$ABLETON_SOURCE/Ableton Live 11-12/Remote Scripts/CL_Arrangement_Builder_Live"
BUILDER_REMOTE_TARGET="$REMOTE_SCRIPTS/CL_Arrangement_Builder_Live"

M4L_SOURCE="$ABLETON_SOURCE/Max for Live à installer"
M4L_TARGET="$HOME/Music/Ableton/User Library/Presets/Audio Effects/Max Audio Effect/CL Audio Controller"

STAMP="$(date '+%Y-%m-%d_%H%M%S')"

backup_existing() {
    local target="$1"

    if [[ -e "$target" ]]; then
        local backup="${target}.sauvegarde_${STAMP}"

        echo "Sauvegarde :"
        echo "  $target"
        echo "→ $backup"

        mv "$target" "$backup"
    fi
}

require_source() {
    local source="$1"

    if [[ ! -e "$source" ]]; then
        echo
        echo "ERREUR : élément absent du kit :"
        echo "  $source"
        exit 1
    fi
}

install_app() {
    local source="$1"
    local target="$2"

    require_source "$source"

    echo
    echo "Installation : $(basename "$target")"

    backup_existing "$target"
    ditto "$source" "$target"
}

clear

echo "============================================================"
echo " INSTALLATION DE LA SUITE CL"
echo "============================================================"
echo
echo "Applications principales"
echo "  • CL Show Control"
echo "  • CL ShowCue"
echo "  • CL Cue Editor"
echo
echo "Production"
echo "  • CL Arrangement Builder"
echo "  • CL Audio Export"
echo "  • CL Ableton Remote"
echo
echo "MIDI & Réseau"
echo "  • CL MIDI Network Manager"
echo "  • CL MIDI RTP Agent"
echo "  • CL MIDI & RTP Diagnostic"
echo "  • CL MIDI Analyzer"
echo "  • CL MIDI Performance Monitor"
echo
echo "Ableton"
echo "  • AbletonOSC"
echo "  • Remote Script Arrangement Builder"
echo "  • Max for Live"
echo
echo "Cette installation ne demande pas de mot de passe administrateur."
echo "Fermez Ableton Live et les applications CL avant de continuer."
echo

read -r -p "Continuer ? (o/n) " answer

case "$answer" in
    o|O|oui|OUI|y|Y|yes|YES) ;;
    *)
        echo "Installation annulée."
        exit 0
        ;;
esac

mkdir -p \
    "$USER_APPS" \
    "$PROD_APPS" \
    "$MIDI_APPS" \
    "$REMOTE_SCRIPTS" \
    "$(dirname "$M4L_TARGET")"

echo
echo "============================================================"
echo " APPLICATIONS PRINCIPALES"
echo "============================================================"

install_app \
    "$PRIMARY_SOURCE/CL Show Control.app" \
    "$USER_APPS/CL Show Control.app"

install_app \
    "$PRIMARY_SOURCE/CL ShowCue.app" \
    "$USER_APPS/CL ShowCue.app"

install_app \
    "$PRIMARY_SOURCE/CL Cue Editor.app" \
    "$USER_APPS/CL Cue Editor.app"

# Nettoyage des anciens noms uniquement par sauvegarde.
backup_existing "$USER_APPS/CL Audio Show Control.app"
backup_existing "$USER_APPS/CL Audio Controller.app"
backup_existing "$USER_APPS/CL ShowCue Builder.app"

echo
echo "============================================================"
echo " PRODUCTION"
echo "============================================================"

install_app \
    "$PROD_SOURCE/CL Arrangement Builder.app" \
    "$PROD_APPS/CL Arrangement Builder.app"

install_app \
    "$PROD_SOURCE/CL Audio Export.app" \
    "$PROD_APPS/CL Audio Export.app"

install_app \
    "$PROD_SOURCE/CL Ableton Remote.app" \
    "$PROD_APPS/CL Ableton Remote.app"

backup_existing "$USER_APPS/Arrangement Builder Live.app"
backup_existing "$USER_APPS/CL Show Audio Builder.app"

echo
echo "============================================================"
echo " MIDI & RÉSEAU"
echo "============================================================"

for app in \
    "CL MIDI Network Manager.app" \
    "CL MIDI RTP Agent.app" \
    "CL MIDI & RTP Diagnostic.app" \
    "CL MIDI Analyzer.app" \
    "CL MIDI Performance Monitor.app"
do
    install_app \
        "$MIDI_SOURCE/$app" \
        "$MIDI_APPS/$app"
done

echo
echo "============================================================"
echo " ABLETON"
echo "============================================================"

require_source "$ABLETONOSC_SOURCE"

echo
echo "Installation AbletonOSC"
backup_existing "$ABLETONOSC_TARGET"
ditto "$ABLETONOSC_SOURCE" "$ABLETONOSC_TARGET"

require_source "$BUILDER_REMOTE_SOURCE"

echo
echo "Installation Remote Script CL Arrangement Builder"
backup_existing "$BUILDER_REMOTE_TARGET"
ditto "$BUILDER_REMOTE_SOURCE" "$BUILDER_REMOTE_TARGET"

require_source "$M4L_SOURCE"

echo
echo "Installation Max for Live"
backup_existing "$M4L_TARGET"
ditto "$M4L_SOURCE" "$M4L_TARGET"

echo
echo "============================================================"
echo " INSTALLATION TERMINÉE"
echo "============================================================"
echo
echo "Applications principales :"
echo "  $USER_APPS"
echo
echo "Production :"
echo "  $PROD_APPS"
echo
echo "MIDI & Réseau :"
echo "  $MIDI_APPS"
echo
echo "Ableton Remote Scripts :"
echo "  $REMOTE_SCRIPTS"
echo
echo "Max for Live :"
echo "  $M4L_TARGET"
echo

open -R "$USER_APPS/CL Show Control.app" >/dev/null 2>&1 || true

read -r -p "Appuyez sur Entrée pour fermer cette fenêtre." _
