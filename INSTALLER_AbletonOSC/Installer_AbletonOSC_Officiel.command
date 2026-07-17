#!/bin/bash
set -e
TARGET="$HOME/Music/Ableton/User Library/Remote Scripts"
TMP="$(mktemp -d)"
URL="https://github.com/ideoforms/AbletonOSC/archive/refs/heads/master.zip"
clear
cat <<'BANNER'
============================================================
 INSTALLATION ABLETON OSC - SOURCE OFFICIELLE GITHUB
============================================================
BANNER
echo "⚠️  Info importante : le dépôt officiel AbletonOSC annonce Ableton Live 11 ou plus."
echo "   Avec Live 10, il faut tester ou utiliser une ancienne version compatible."
echo ""
read -p "Continuer l'installation officielle AbletonOSC ? (o/n) " ANSWER
case "$ANSWER" in o|O|oui|OUI|y|Y|yes|YES) ;; *) echo "Installation annulée."; exit 0;; esac
mkdir -p "$TARGET"
echo "ℹ️  Téléchargement AbletonOSC..."
curl -L "$URL" -o "$TMP/AbletonOSC.zip"
echo "✅ Téléchargé"
unzip -q "$TMP/AbletonOSC.zip" -d "$TMP"
SRC="$(find "$TMP" -maxdepth 1 -type d -name 'AbletonOSC-*' | head -1)"
if [ -z "$SRC" ]; then echo "❌ Dossier AbletonOSC introuvable après extraction."; exit 1; fi
rm -rf "$TARGET/AbletonOSC"
cp -R "$SRC" "$TARGET/AbletonOSC"
echo "✅ AbletonOSC copié dans :"
echo "$TARGET/AbletonOSC"
echo ""
echo "ÉTAPES DANS ABLETON LIVE :"
echo "1. Redémarre Ableton Live."
echo "2. Préférences > Link/Tempo/MIDI."
echo "3. Surface de contrôle : AbletonOSC."
echo "4. Entrée/Sortie : None si demandé."
echo "5. Lance Ableton Web Remote.app."
open "$TARGET" >/dev/null 2>&1 || true
osascript -e 'display dialog "AbletonOSC a été installé dans User Library / Remote Scripts. Redémarre Ableton Live puis choisis AbletonOSC dans les surfaces de contrôle." buttons {"OK"} default button 1 with icon note' >/dev/null 2>&1 || true
