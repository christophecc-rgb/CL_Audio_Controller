#!/bin/bash
clear
echo "============================================================"
echo " DIAGNOSTIC ABLETON WEB REMOTE"
echo "============================================================"
echo ""
echo "Python :"
python3 --version 2>/dev/null || echo "Python 3 introuvable"
echo ""
echo "Adresse réseau :"
ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "IP introuvable"
echo ""
echo "Process serveur :"
pgrep -fl "app.py" || echo "Serveur non détecté"
echo ""
echo "Ports utiles :"
lsof -nP -iUDP:11001 2>/dev/null || echo "Port retour OSC 11001 non visible"
lsof -nP -iTCP:5050 2>/dev/null || echo "Port web 5050 non visible"
echo ""
echo "AbletonOSC installé ?"
if [ -d "$HOME/Music/Ableton/User Library/Remote Scripts/AbletonOSC" ]; then
  echo "✅ AbletonOSC trouvé"
else
  echo "❌ AbletonOSC non trouvé dans User Library/Remote Scripts"
fi
echo ""
echo "Log serveur : $HOME/Library/Application Support/Ableton Web Remote/server.log"
echo ""
read -p "Appuie sur Entrée pour fermer..."
