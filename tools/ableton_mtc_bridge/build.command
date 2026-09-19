#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/CLAbletonMTCBridge.m"
OUT="$ROOT/CLAbletonMTCBridge"

echo "========================================"
echo " BUILD CL ABLETON MTC BRIDGE UNIVERSAL2"
echo "========================================"

clang \
  -fobjc-arc \
  -fblocks \
  -arch arm64 \
  -arch x86_64 \
  -mmacosx-version-min=11.0 \
  "$SRC" \
  -framework Foundation \
  -framework CoreMIDI \
  -o "$OUT"

chmod +x "$OUT"

/usr/bin/codesign \
  --force \
  --sign - \
  "$OUT"

/usr/bin/codesign \
  --verify \
  --strict \
  "$OUT"

ARCHS="$(/usr/bin/lipo -archs "$OUT")"

echo "Architectures : $ARCHS"

[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || {
  echo "ERREUR : le bridge n'est pas universal2"
  exit 1
}

echo
echo "BUILD UNIVERSAL2 OK"
echo "$OUT"
