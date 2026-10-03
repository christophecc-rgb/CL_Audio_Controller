#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/CLAbletonMTCBridge.m"
OUT="${1:-$ROOT/CLAbletonMTCBridge}"
mkdir -p "$(dirname "$OUT")"
BUILD_DIR="$(mktemp -d "$(dirname "$OUT")/.cl-mtc-bridge.XXXXXX")"
# Only remove this invocation's temporary compilation files.
trap 'rm -f "$BUILD_DIR/arm64" "$BUILD_DIR/x86_64" "$BUILD_DIR/CLAbletonMTCBridge"; rmdir "$BUILD_DIR"' EXIT

echo "========================================"
echo " BUILD CL ABLETON MTC BRIDGE UNIVERSAL2"
echo "========================================"

for ARCH in arm64 x86_64; do
  /usr/bin/clang \
    -fobjc-arc \
    -fblocks \
    -arch "$ARCH" \
    -mmacosx-version-min=11.0 \
    "$SRC" \
    -framework Foundation \
    -framework CoreMIDI \
    -o "$BUILD_DIR/$ARCH"
done

/usr/bin/lipo -create "$BUILD_DIR/arm64" "$BUILD_DIR/x86_64" \
  -output "$BUILD_DIR/CLAbletonMTCBridge"
chmod +x "$BUILD_DIR/CLAbletonMTCBridge"
/usr/bin/codesign --force --sign - "$BUILD_DIR/CLAbletonMTCBridge"
/usr/bin/codesign --verify --strict --verbose=2 "$BUILD_DIR/CLAbletonMTCBridge"
/usr/bin/lipo "$BUILD_DIR/CLAbletonMTCBridge" -verify_arch arm64 x86_64
ARCHS="$(/usr/bin/lipo -archs "$BUILD_DIR/CLAbletonMTCBridge")"
echo "Architectures : $ARCHS"
case "$ARCHS" in
  "arm64 x86_64"|"x86_64 arm64") ;;
  *) echo "ERREUR : le bridge n'est pas universal2 ($ARCHS)" >&2; exit 1 ;;
esac

# Publish only after both compilations, the signature and architecture checks pass.
mv -f "$BUILD_DIR/CLAbletonMTCBridge" "$OUT"

echo
echo "BUILD UNIVERSAL2 OK"
echo "$OUT"
