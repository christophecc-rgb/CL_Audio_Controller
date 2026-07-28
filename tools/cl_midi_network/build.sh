#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
OUTPUT_DIR="${1:-$SCRIPT_DIR/build}"
mkdir -p "$OUTPUT_DIR"

clang -arch arm64 -arch x86_64 -fobjc-arc -fblocks \
  -framework Foundation -framework CoreMIDI \
  "$SCRIPT_DIR/CLMIDINetworkGuardian.m" \
  -o "$OUTPUT_DIR/CLMIDINetworkGuardian"

clang -arch arm64 -arch x86_64 -fobjc-arc -fblocks \
  -framework Foundation -framework CoreMIDI \
  "$SCRIPT_DIR/CLYamahaConsoleSimulator.m" \
  -o "$OUTPUT_DIR/CLYamahaConsoleSimulator"

clang -arch arm64 -arch x86_64 -fobjc-arc -fblocks \
  -framework Foundation -framework CoreMIDI \
  "$SCRIPT_DIR/CLMIDIRoundTripTester.m" \
  -o "$OUTPUT_DIR/CLMIDIRoundTripTester"

clang -arch arm64 -arch x86_64 -fobjc-arc -fblocks \
  -framework AppKit -framework Foundation -framework CoreMIDI -framework QuartzCore \
  "$SCRIPT_DIR/CLMIDINetworkDashboard.m" \
  -o "$OUTPUT_DIR/CLMIDINetworkDashboard"

echo "$OUTPUT_DIR/CLMIDINetworkGuardian"
echo "$OUTPUT_DIR/CLYamahaConsoleSimulator"
echo "$OUTPUT_DIR/CLMIDIRoundTripTester"
echo "$OUTPUT_DIR/CLMIDINetworkDashboard"
