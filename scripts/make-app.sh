#!/bin/bash
# Assemble a runnable Replay.app from the SPM build.
#
# Swift Package Manager produces a bare executable; macOS wants a bundle with an
# Info.plist. This wraps one around it so the app can be launched, appear in the Dock,
# and run as a menu-bar app — a faster development loop than a full Xcode build, and it
# works with Command Line Tools alone.
#
# The ad-hoc signature below is NOT enough to distribute: that needs a Developer ID
# signature and notarisation, and a stable Xcode rather than the beta. See
# docs/PORTING-MAP.md.
#
#   ./scripts/make-app.sh [debug|release]

set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Replay.app"
BUNDLE_ID="app.replay.native"
VERSION="0.1.0"

echo "Building ($CONFIG)…"
swift build -c "$CONFIG" --package-path "$ROOT"

BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/ReplayApp"
[ -x "$BIN" ] || { echo "no executable at $BIN" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Replay"

# The product's own icon, carried over from the Glaze app so the two are visibly the
# same product. Glaze gitignores it as generated output, so this repo keeps a copy.
ICON="$ROOT/Resources/AppIcon.icns"
if [ -f "$ICON" ]; then
    cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "  note: Resources/AppIcon.icns missing — the app will use the generic icon"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>Replay</string>
  <key>CFBundleDisplayName</key>       <string>Replay</string>
  <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key>        <string>Replay</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key>           <string>$VERSION</string>
  <key>CFBundleIconFile</key>          <string>AppIcon</string>
  <key>NSHumanReadableCopyright</key>  <string>Copyright © 2026 Nurkamol Vakhidov. MIT License.</string>
  <key>LSMinimumSystemVersion</key>    <string>26.0</string>
  <!-- Replay records only which app is frontmost, so it needs no usage
       descriptions: no camera, microphone, location, or screen recording. If a
       key like NSScreenCaptureUsageDescription ever becomes necessary, something
       has gone wrong — see CLAUDE.md. -->
  <key>NSHighResolutionCapable</key>   <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough for local launch, not for distribution.
codesign --force --sign - "$APP" >/dev/null 2>&1 \
  && echo "Signed ad-hoc." \
  || echo "Could not sign; the app may still run locally."

echo "Built $APP"
echo "Run with: open '$APP'   (or '$APP/Contents/MacOS/Replay' to see stdout)"
