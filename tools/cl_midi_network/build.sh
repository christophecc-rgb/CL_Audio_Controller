#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
OUTPUT_DIR="${1:-$SCRIPT_DIR/build}"
mkdir -p "$OUTPUT_DIR"

clang -arch arm64 -arch x86_64 -mmacosx-version-min=10.15 -fobjc-arc -fblocks \
  -framework Foundation -framework CoreMIDI \
  "$SCRIPT_DIR/CLMIDINetworkGuardian.m" \
  -o "$OUTPUT_DIR/CLMIDINetworkGuardian"

clang -arch arm64 -arch x86_64 -mmacosx-version-min=10.15 -fobjc-arc -fblocks \
  -framework AppKit -framework Foundation -framework CoreMIDI \
  "$SCRIPT_DIR/CLMIDIRTPAgent.m" \
  -o "$OUTPUT_DIR/CLMIDIRTPAgent"

clang -arch arm64 -arch x86_64 -mmacosx-version-min=10.15 -fobjc-arc -fblocks \
  -framework Foundation -framework CoreMIDI \
  "$SCRIPT_DIR/CLYamahaConsoleSimulator.m" \
  -o "$OUTPUT_DIR/CLYamahaConsoleSimulator"

clang -arch arm64 -arch x86_64 -mmacosx-version-min=10.15 -fobjc-arc -fblocks \
  -framework Foundation -framework CoreMIDI \
  "$SCRIPT_DIR/CLYamahaConsoleSimulator.m" \
  -o "$OUTPUT_DIR/CLMIDIRTPResponder"

clang -arch arm64 -arch x86_64 -mmacosx-version-min=10.15 -fobjc-arc -fblocks \
  -framework Foundation -framework CoreMIDI \
  "$SCRIPT_DIR/CLMIDIRoundTripTester.m" \
  -o "$OUTPUT_DIR/CLMIDIRoundTripTester"

clang -arch arm64 -arch x86_64 -mmacosx-version-min=10.15 -fobjc-arc -fblocks \
  -framework AppKit -framework Foundation -framework CoreMIDI -framework QuartzCore \
  "$SCRIPT_DIR/CLMIDINetworkDashboard.m" \
  -o "$OUTPUT_DIR/CLMIDINetworkDashboard"

clang -arch arm64 -arch x86_64 -mmacosx-version-min=10.15 -fobjc-arc -fblocks \
  -framework AppKit -framework Foundation -framework CoreMIDI -framework QuartzCore \
  "$SCRIPT_DIR/CLYamahaSimulatorDashboard.m" \
  -o "$OUTPUT_DIR/CLYamahaSimulatorDashboard"

clang -arch arm64 -arch x86_64 -mmacosx-version-min=10.15 -fobjc-arc -fblocks \
  -framework AppKit -framework Foundation -framework CoreMIDI \
  "$SCRIPT_DIR/CLMIDIPerformanceMonitor.m" \
  -o "$OUTPUT_DIR/CLMIDIPerformanceMonitor"

clang -arch arm64 -arch x86_64 -mmacosx-version-min=10.15 \
  -fobjc-arc -fblocks \
  -framework Foundation -framework CoreMIDI \
  "$SCRIPT_DIR/CLMIDICore.m" \
  "$SCRIPT_DIR/CLMIDILogger.m" \
  "$SCRIPT_DIR/CLMIDICoreMIDIAnalyzer.m" \
  -o "$OUTPUT_DIR/CLMIDICoreMIDIAnalyzer"
echo "$OUTPUT_DIR/CLMIDINetworkGuardian"
echo "$OUTPUT_DIR/CLMIDIRTPAgent"
echo "$OUTPUT_DIR/CLYamahaConsoleSimulator"
echo "$OUTPUT_DIR/CLMIDIRTPResponder"
echo "$OUTPUT_DIR/CLMIDIRoundTripTester"
echo "$OUTPUT_DIR/CLMIDINetworkDashboard"
echo "$OUTPUT_DIR/CLYamahaSimulatorDashboard"
echo "$OUTPUT_DIR/CLMIDIPerformanceMonitor"
echo "$OUTPUT_DIR/CLMIDICoreMIDIAnalyzer"
