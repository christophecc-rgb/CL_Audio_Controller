#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${1:-$HOME/Desktop/Créer le Kit CL.app}"
CONTENTS="$DESTINATION/Contents"

if [[ -e "$DESTINATION" ]]; then
  echo "L’application existe déjà : $DESTINATION" >&2
  echo "Déplacez-la ou supprimez-la explicitement avant de la recréer." >&2
  exit 1
fi

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
ditto "$PROJECT_ROOT/packaging/Creer_Le_Kit_CL.app.sh" "$CONTENTS/MacOS/Créer le Kit CL"
ditto "$PROJECT_ROOT/CL_AUDIO.icns" "$CONTENTS/Resources/CL_AUDIO.icns"
printf '%s\n' "$PROJECT_ROOT" > "$CONTENTS/Resources/PROJECT_ROOT.txt"
chmod +x "$CONTENTS/MacOS/Créer le Kit CL"

cat > "$CONTENTS/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>Créer le Kit CL</string>
<key>CFBundleExecutable</key><string>Créer le Kit CL</string>
<key>CFBundleIconFile</key><string>CL_AUDIO.icns</string>
<key>CFBundleIdentifier</key><string>com.claudio.kit-builder</string>
<key>CFBundleName</key><string>Créer le Kit CL</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>LSMinimumSystemVersion</key><string>10.15</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF

echo "$DESTINATION"
