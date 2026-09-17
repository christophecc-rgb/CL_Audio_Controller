#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-$PROJECT_ROOT/dist/configuration-checker/icon}"
BASE_ICON="$PROJECT_ROOT/assets/app_icons/CL_MIDI_RTP_Diagnostic.png"
GENERATOR="$PROJECT_ROOT/scripts/generate_app_icon_variants.py"
ICONSET="$OUTPUT_DIR/CLAudioConfigurationChecker.iconset"

"${CL_PYTHON:-$PROJECT_ROOT/.venv/bin/python}" "$GENERATOR"

[[ -f "$BASE_ICON" ]] || { echo "Icône CL AUDIO source absente: $BASE_ICON" >&2; exit 1; }
[[ -f "$GENERATOR" ]] || { echo "Générateur absent: $GENERATOR" >&2; exit 1; }

mkdir -p "$OUTPUT_DIR"
MASTER="$OUTPUT_DIR/CLAudioConfigurationChecker-1024.png"
/usr/bin/ditto "$BASE_ICON" "$MASTER"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

for spec in \
  "16 icon_16x16.png" "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
  pixels="${spec%% *}"
  filename="${spec#* }"
  /usr/bin/sips -z "$pixels" "$pixels" "$MASTER" --out "$ICONSET/$filename" >/dev/null
done

/usr/bin/iconutil -c icns "$ICONSET" -o "$OUTPUT_DIR/CLAudioConfigurationChecker.icns"
echo "$OUTPUT_DIR/CLAudioConfigurationChecker.icns"
