#!/bin/bash
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "========================================"
echo " BUILD CL ABLETON MTC BRIDGE"
echo "========================================"

clang \
  -fobjc-arc \
  -fblocks \
  "$ROOT/CLAbletonMTCBridge.m" \
  -framework Foundation \
  -framework CoreMIDI \
  -o "$ROOT/CLAbletonMTCBridge"

chmod +x "$ROOT/CLAbletonMTCBridge"

echo
echo "BUILD OK"
echo "$ROOT/CLAbletonMTCBridge"
