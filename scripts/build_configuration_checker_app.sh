#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$PROJECT_ROOT/scripts/generate_app_icon_variants.py"
VERSION="${1:-0.1.0}"
OUTPUT_ROOT="${2:-$PROJECT_ROOT/dist/configuration-checker}"
APP_NAME="CL MIDI & RTP Diagnostic"
PLIST_APP_NAME="CL MIDI &amp; RTP Diagnostic"
BUNDLE_ID="com.claudio.configurationchecker"
APP_PATH="$OUTPUT_ROOT/$APP_NAME.app"
WORK_DIR="$(mktemp -d /private/tmp/CLAudioConfigurationChecker.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Version invalide: $VERSION" >&2; exit 2; }
mkdir -p "$WORK_DIR/$APP_NAME.app/Contents/MacOS" "$WORK_DIR/$APP_NAME.app/Contents/Resources" "$OUTPUT_ROOT"

/usr/bin/clang -arch arm64 -arch x86_64 -mmacosx-version-min=10.15 -fobjc-arc -fblocks \
  -framework AppKit -framework Foundation -framework CoreMIDI \
  "$PROJECT_ROOT/tools/cl_midi_network/CLConfigurationProfile.m" \
  "$PROJECT_ROOT/tools/cl_midi_network/CLConfigurationInspector.m" \
  "$PROJECT_ROOT/tools/cl_midi_network/CLConfigurationValidator.m" \
  "$PROJECT_ROOT/tools/cl_midi_network/CLConfigurationCheckerApp.m" \
  -o "$WORK_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"

/usr/bin/ditto "$PROJECT_ROOT/assets/app_icons/CL_MIDI_RTP_Diagnostic.icns" \
  "$WORK_DIR/$APP_NAME.app/Contents/Resources/CLAudioConfigurationChecker.icns"
/usr/bin/ditto "$PROJECT_ROOT/M4L/Devices/CL MIDI Console Monitor/paradis_latin_logo.jpg" \
  "$WORK_DIR/$APP_NAME.app/Contents/Resources/paradis_latin_logo.jpg"

cat > "$WORK_DIR/$APP_NAME.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>$PLIST_APP_NAME</string>
<key>CFBundleExecutable</key><string>$PLIST_APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleIconFile</key><string>CLAudioConfigurationChecker.icns</string>
<key>CFBundleName</key><string>$PLIST_APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>10.15</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF

/usr/bin/plutil -lint "$WORK_DIR/$APP_NAME.app/Contents/Info.plist" >/dev/null
/usr/bin/xattr -cr "$WORK_DIR/$APP_NAME.app"
/usr/bin/codesign --force --deep --sign - "$WORK_DIR/$APP_NAME.app"
rm -rf "$APP_PATH"
/usr/bin/ditto "$WORK_DIR/$APP_NAME.app" "$APP_PATH"
/usr/bin/codesign --verify --deep --strict "$APP_PATH"
echo "$APP_PATH"
