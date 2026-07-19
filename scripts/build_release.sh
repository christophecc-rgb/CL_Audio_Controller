#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$PROJECT_ROOT"

echo "========== BUILD =========="

pyinstaller "CL Audio Controller.spec"

echo
echo "========== DMG =========="

cd dist

rm -f CL_Audio_Controller.dmg

hdiutil create \
    -volname "CL Audio Controller" \
    -srcfolder "CL Audio Controller.app" \
    -format UDZO \
    -o CL_Audio_Controller.dmg

echo
echo "========== RELEASE =========="

mkdir -p "$PROJECT_ROOT/Releases"

DATE=$(date +"%Y-%m-%d_%H-%M-%S")

cp CL_Audio_Controller.dmg \
"$PROJECT_ROOT/Releases/CL_Audio_Controller_${DATE}.dmg"

echo
echo "✅ Release créée :"

ls -lh "$PROJECT_ROOT/Releases"/CL_Audio_Controller_${DATE}.dmg
