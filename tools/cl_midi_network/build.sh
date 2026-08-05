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

FRAMEWORK_SOURCES=(CLCommand CLMIDICore CLMIDICommandInterpreter CLMIDIEvent CLMIDILogger CLMIDIPacket CLMIDIPort)
FRAMEWORK_OBJECTS=()
mkdir -p "$OUTPUT_DIR/framework-objects"
for source_name in $FRAMEWORK_SOURCES; do
  object_path="$OUTPUT_DIR/framework-objects/$source_name.o"
  clang -arch arm64 -arch x86_64 -mmacosx-version-min=10.15 -fobjc-arc -fblocks \
    -c "$SCRIPT_DIR/$source_name.m" -o "$object_path"
  FRAMEWORK_OBJECTS+=("$object_path")
done
libtool -static -o "$OUTPUT_DIR/libCLMIDIFramework.a" $FRAMEWORK_OBJECTS

MACOSX_DEPLOYMENT_TARGET=10.15 clang -arch arm64 -arch x86_64 -fobjc-arc -fblocks \
  -framework Foundation -framework CoreMIDI \
  "$SCRIPT_DIR/CLMIDICoreMIDIAnalyzer.m" "$OUTPUT_DIR/libCLMIDIFramework.a" \
  -o "$OUTPUT_DIR/CLMIDICoreMIDIAnalyzer"

MACOSX_DEPLOYMENT_TARGET=10.15 clang -arch arm64 -arch x86_64 -fobjc-arc -fblocks \
  -framework Foundation -framework CoreMIDI \
  "$SCRIPT_DIR/CLMIDIMonitor.m" "$OUTPUT_DIR/libCLMIDIFramework.a" \
  -o "$OUTPUT_DIR/CLMIDIMonitor"

MACOSX_DEPLOYMENT_TARGET=10.15 clang -arch arm64 -arch x86_64 -fobjc-arc -fblocks \
  -framework Foundation -framework CoreMIDI \
  "$SCRIPT_DIR/CLLogicTransportState.m" \
  "$SCRIPT_DIR/CLLogicTransportAdapter.m" \
  "$SCRIPT_DIR/CLLogicBridge.m" \
  "$SCRIPT_DIR/CLLogicBridgeMain.m" \
  "$OUTPUT_DIR/libCLMIDIFramework.a" \
  -o "$OUTPUT_DIR/CLLogicBridge"
echo "$OUTPUT_DIR/CLMIDINetworkGuardian"
echo "$OUTPUT_DIR/CLMIDIRTPAgent"
echo "$OUTPUT_DIR/CLYamahaConsoleSimulator"
echo "$OUTPUT_DIR/CLMIDIRTPResponder"
echo "$OUTPUT_DIR/CLMIDIRoundTripTester"
echo "$OUTPUT_DIR/CLMIDINetworkDashboard"
echo "$OUTPUT_DIR/CLYamahaSimulatorDashboard"
echo "$OUTPUT_DIR/CLMIDIPerformanceMonitor"
echo "$OUTPUT_DIR/CLMIDICoreMIDIAnalyzer"
echo "$OUTPUT_DIR/CLMIDIMonitor"
echo "$OUTPUT_DIR/CLLogicBridge"
