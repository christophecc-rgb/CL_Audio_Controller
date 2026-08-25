#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
OUTPUT_ROOT="${2:-$PROJECT_ROOT/dist/configuration-checker}"
APP_NAME="CL Audio Configuration Checker"
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

"$PROJECT_ROOT/scripts/generate_configuration_checker_icon.sh" "$WORK_DIR/icon" >/dev/null
/usr/bin/ditto "$WORK_DIR/icon/CLAudioConfigurationChecker.icns" \
  "$WORK_DIR/$APP_NAME.app/Contents/Resources/CLAudioConfigurationChecker.icns"

cat > "$WORK_DIR/$APP_NAME.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleIconFile</key><string>CLAudioConfigurationChecker.icns</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>10.15</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF

/usr/bin/plutil -lint "$WORK_DIR/$APP_NAME.app/Contents/Info.plist" >/dev/null
/usr/bin/codesign --force --deep --sign - "$WORK_DIR/$APP_NAME.app"
rm -rf "$APP_PATH"
/usr/bin/ditto "$WORK_DIR/$APP_NAME.app" "$APP_PATH"
/usr/bin/codesign --verify --deep --strict "$APP_PATH"
echo "$APP_PATH"
