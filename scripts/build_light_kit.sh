#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CL_PYTHON="${CL_PYTHON:-$PROJECT_ROOT/.venv/bin/python}"
export CL_AUDIO_VERSION="${CL_AUDIO_VERSION:-$("$CL_PYTHON" "$PROJECT_ROOT/release_version.py")}"
export CL_BUILD_NUMBER="${CL_BUILD_NUMBER:-$("$CL_PYTHON" "$PROJECT_ROOT/release_version.py" --build)}"
export CL_BUILD_ARCH="${CL_BUILD_ARCH:-universal2}"
OUTPUT="${CL_LIGHT_OUTPUT_ROOT:-$PROJECT_ROOT/Releases/CL_Kit_Light_$CL_AUDIO_VERSION}"
WORK="$(mktemp -d /private/tmp/CL_Light_Kit_XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
KIT_NAME="CL_Kit_Light_${CL_AUDIO_VERSION}_${CL_BUILD_ARCH}"
KIT="$WORK/$KIT_NAME"
mkdir -p "$OUTPUT" "$KIT/Applications" "$KIT/Ableton/Remote Scripts" "$KIT/Documentation"
cd "$PROJECT_ROOT"
"$CL_PYTHON" -m PyInstaller --clean --noconfirm --workpath "$WORK/work" --distpath "$WORK/dist" "CL Show Control Light.spec"
ditto "$WORK/dist/CL Show Control Light.app" "$KIT/Applications/CL Show Control Light.app"
# Same AbletonOSC source and local compatibility patches used by FULL.
git -C "$PROJECT_ROOT/../AbletonOSC" archive HEAD | tar -x -C "$KIT/Ableton/Remote Scripts"
mv "$KIT/Ableton/Remote Scripts/abletonosc" "$WORK/abletonosc-module"
mkdir -p "$KIT/Ableton/Remote Scripts/AbletonOSC"
# Preserve repository root files required by the control surface.
find "$KIT/Ableton/Remote Scripts" -mindepth 1 -maxdepth 1 ! -name AbletonOSC -exec mv {} "$KIT/Ableton/Remote Scripts/AbletonOSC/" \;
mv "$WORK/abletonosc-module" "$KIT/Ableton/Remote Scripts/AbletonOSC/abletonosc"
"$CL_PYTHON" "$PROJECT_ROOT/INSTALLER_AbletonOSC/install_bonjour.py" --target "$KIT/Ableton/Remote Scripts/AbletonOSC"
"$CL_PYTHON" "$PROJECT_ROOT/INSTALLER_AbletonOSC/install_fast_poll.py" --target "$KIT/Ableton/Remote Scripts/AbletonOSC"

# Remove development-only files from the staged plugin, never from its source.
for CL_PLUGIN_EXTRA in tests scripts .github .gitignore CONTRIBUTING.md run-console.py __init__.py.before-cl-bonjour manager.py.before-cl-fast-poll; do
  rm -rf "$KIT/Ableton/Remote Scripts/AbletonOSC/$CL_PLUGIN_EXTRA"
done
"$CL_PYTHON" "$PROJECT_ROOT/scripts/stamp_release_bundles.py" "$KIT/Applications" --version "$CL_AUDIO_VERSION" --build "$CL_BUILD_NUMBER" --manifest "$KIT/RELEASE_MANIFEST.json"
codesign --force --deep --sign - "$KIT/Applications/CL Show Control Light.app"
codesign --verify --deep --strict "$KIT/Applications/CL Show Control Light.app"
"$CL_PYTHON" "$PROJECT_ROOT/scripts/verify_macos_architectures.py" "$KIT/Applications" --target "$CL_BUILD_ARCH" --report "$KIT/ARCHITECTURES.json"
cp "$PROJECT_ROOT/packaging/Installer_CL_Light.command" "$KIT/Installer CL Light.command"
cp "$PROJECT_ROOT/docs/RELEASE_2.3.0.md" "$KIT/Documentation/RELEASE_2.3.0.md"
cat > "$KIT/Documentation/INSTALLATION.txt" <<'EOF'
CL Show Control Light — installation locale sans Python requis.
Fermer Ableton Live, lancer « Installer CL Light.command » puis sélectionner
AbletonOSC dans les préférences Surfaces de contrôle de Live 11/12.
Ableton Live et les médias du spectacle ne sont pas inclus.
FULL et Light peuvent être installés côte à côte mais ne doivent pas être
lancés simultanément : ils utilisent les mêmes ports OSC/HTTP/HTTPS.
Le kit ne contient aucun mot de passe, certificat privé ou appareil autorisé.
Configuration et autorisations distantes se font sur le Mac après installation.
Application signée ad hoc, non notarisée : ouverture macOS à confirmer.
EOF
(cd "$KIT"; find . -type f ! -name SHA256SUMS.txt -print0 | sort -z | xargs -0 shasum -a 256 > SHA256SUMS.txt)
ditto -c -k --keepParent --norsrc "$KIT" "$OUTPUT/$KIT_NAME.zip"
(cd "$OUTPUT"; shasum -a 256 "$KIT_NAME.zip" > "$KIT_NAME.sha256")
# Unarchived review copy, never installed into Applications.
ditto "$KIT" "$OUTPUT/$KIT_NAME"
echo "$OUTPUT/$KIT_NAME.zip"
