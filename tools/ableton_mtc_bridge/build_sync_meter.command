#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/build-sync-meter"
APP="$OUT/CL Sync Meter.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for ARCH in arm64 x86_64; do
  /usr/bin/clang -fobjc-arc -fblocks -Wall -Wextra -Wno-unused-parameter \
    -arch "$ARCH" -mmacosx-version-min=11.0 "$ROOT/CLSyncMeter.m" \
    -framework Cocoa -framework CoreMIDI -o "$OUT/CLSyncMeter-$ARCH"
done
/usr/bin/lipo -create "$OUT/CLSyncMeter-arm64" "$OUT/CLSyncMeter-x86_64" -output "$APP/Contents/MacOS/CLSyncMeter"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CLSyncMeter</string>
<key>CFBundleIdentifier</key><string>com.claudio.syncmeter</string>
<key>CFBundleName</key><string>CL Sync Meter</string>
<key>CFBundleDisplayName</key><string>CL Sync Meter</string>
<key>CFBundleIconFile</key><string>CL_MIDI_Performance.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.2</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>11.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
cp "$ROOT/../../assets/app_icons/CL_MIDI_Performance.icns" "$APP/Contents/Resources/CL_MIDI_Performance.icns"
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --strict --verbose=2 "$APP"
/usr/bin/lipo "$APP/Contents/MacOS/CLSyncMeter" -verify_arch arm64 x86_64
printf 'CL Sync Meter universal2 : %s\n' "$APP"
