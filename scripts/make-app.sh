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
# Anything after the configuration goes straight to `swift build`. Arguments rather than an
# environment variable because Homebrew scrubs the environment it hands a build, and an
# option that silently fails to arrive is worse than one that is visible at the call site:
#
#   ./scripts/make-app.sh release --disable-sandbox
#
# which is exactly what the Homebrew formula passes, because SwiftPM's sandbox and
# Homebrew's do not nest — `sandbox-exec: sandbox_apply: Operation not permitted`.
shift 2>/dev/null || true
EXTRA_FLAGS=("$@")
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Replay.app"
BUNDLE_ID="app.replay.native"
VERSION="0.9.2"   # matches the top entry in CHANGELOG.md
MIN_MACOS="26.0"  # CLAUDE.md: the interface leans on APIs that begin at 15 and 26

echo "Building ($CONFIG)…"

# App Intents need metadata generated at build time, and SwiftPM does not do it.
#
# Xcode runs `appintentsmetadataprocessor` as a build phase; a hand-assembled bundle has to
# run it itself, or Shortcuts, Spotlight and Siri simply never see the intents — no error,
# no warning, an app that looks like it has none. The processor reads the constant values
# the compiler emits for the protocols listed in the toolchain's own `AppIntents.json`, so
# the build has to ask for those too.
#
# Both flags are additive: if the toolchain ever drops them the build still succeeds and
# only the metadata step is skipped, which is checked and reported below rather than
# passing silently.
INTENT_PROTOCOLS="$(xcrun --find swiftc | xargs dirname)/../share/swift/SwiftConstantValues/AppIntents.json"
CONST_FLAGS=()
if [ -f "$INTENT_PROTOCOLS" ]; then
  CONST_FLAGS=(-Xswiftc -emit-const-values
               -Xswiftc -Xfrontend -Xswiftc -const-gather-protocols-file
               -Xswiftc -Xfrontend -Xswiftc "$INTENT_PROTOCOLS")
fi

# Tried with the constant-extraction flags, and again without them if that fails.
#
# The flags are how App Intents metadata gets generated, and their spelling is not stable
# across toolchains: Xcode 26.5 rejects the protocol list shipped in its *own* toolchain as
# "malformed", where Xcode 27 accepts it. Found on a Homebrew runner, where the app would
# otherwise simply not build.
#
# Metadata is worth having and is not worth failing a build for. Someone installing the app
# wants the app; Shortcuts support is the part that can be missing and said so. The retry
# also means this keeps working on whatever Xcode ships next, whichever way the flag goes.
if ! swift build -c "$CONFIG" --package-path "$ROOT" \
        ${CONST_FLAGS[@]+"${CONST_FLAGS[@]}"} ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} 2>&1
then
    if [ ${#CONST_FLAGS[@]} -gt 0 ]; then
        echo "  note: this toolchain rejected the App Intents constant-extraction flags."
        echo "        Building without them — Shortcuts and Spotlight will not see any"
        echo "        intents from this build. Everything else is unaffected."
        CONST_FLAGS=()
        swift build -c "$CONFIG" --package-path "$ROOT" \
            ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"}
    else
        exit 1
    fi
fi

BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" \
    ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} --show-bin-path)/ReplayApp"
[ -x "$BIN" ] || { echo "no executable at $BIN" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Replay"

# The package's resource bundles, which hold the strings catalogue.
#
# **Not optional, and not a nicety.** SwiftPM's generated `Bundle.module` calls `fatalError`
# when it cannot find its bundle — so an app assembled without this does not fall back to
# English, it dies on the first line of copy it tries to read. That is exactly what happened
# the day the catalogue was added: the app launched, and was gone by the time the menu bar
# drew its tooltip. Nothing else catches it, because every test runs where the bundle is.
BIN_DIR="$(dirname "$BIN")"
BUNDLES=0
for BUNDLE in "$BIN_DIR"/*.bundle; do
    [ -d "$BUNDLE" ] || continue
    # Never the test bundle. It carries a probe catalogue in a language nobody has
    # translated, and shipping it would make macOS believe Replay supports that language —
    # one translated line among four hundred English ones, which is worse than no claim.
    case "$(basename "$BUNDLE")" in *Tests.bundle) continue ;; esac
    cp -R "$BUNDLE" "$APP/Contents/Resources/"
    BUNDLES=$((BUNDLES + 1))
done
if [ "$BUNDLES" = "0" ]; then
    echo "make-app: no resource bundles found in $BIN_DIR — the app would crash on its" >&2
    echo "make-app: first localised string. Refusing to assemble one." >&2
    exit 1
fi

# The product's own icon, carried over from the Glaze app so the two are visibly the
# same product. Glaze gitignores it as generated output, so this repo keeps a copy.
# The App Intents metadata, into Contents/Resources where the system looks for it.
PROCESSOR="$(xcrun --find swiftc | xargs dirname)/appintentsmetadataprocessor"
CONSTVALS="$(find "$ROOT/.build" -path "*ReplayApp-p.build*" -name "*.swiftconstvalues" 2>/dev/null)"
if [ -x "$PROCESSOR" ] && [ -n "$CONSTVALS" ]; then
  WORK="$(mktemp -d)"
  find "$ROOT/Sources/ReplayApp" -name "*.swift" > "$WORK/sources.txt"
  printf '%s\n' $CONSTVALS > "$WORK/constvals.txt"
  "$PROCESSOR" \
    --output "$APP/Contents/Resources" \
    --toolchain-dir "$(xcrun --find swiftc | xargs dirname)/.." \
    --module-name ReplayApp \
    --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
    --xcode-version "$(xcodebuild -version 2>/dev/null | tail -1 | awk '{print $3}')" \
    --platform-family macOS \
    --deployment-target "$MIN_MACOS" \
    --target-triple "$(uname -m)-apple-macos$MIN_MACOS" \
    --source-file-list "$WORK/sources.txt" \
    --swift-const-vals-list "$WORK/constvals.txt" \
    --force >/dev/null 2>&1
  rm -rf "$WORK"
fi
if [ -d "$APP/Contents/Resources/Metadata.appintents" ]; then
  INTENTS=$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['actions']))" \
    "$APP/Contents/Resources/Metadata.appintents/extract.actionsdata" 2>/dev/null || echo "?")
  echo "  App Intents: $INTENTS, discoverable by Shortcuts and Spotlight."
else
  # Loud, because the failure mode is an app that silently has no Shortcuts support.
  echo "  warning: no App Intents metadata — Shortcuts will not see any intents." >&2
fi

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
# A Developer ID if one was handed in, ad-hoc otherwise.
#
# `REPLAY_SIGN_IDENTITY` is how `make-dmg.sh --release` and the release workflow ask for a
# real signature. Deep and hardened-runtime, because notarisation refuses anything less, and
# `--options runtime` has to be on the app before the disk image is built rather than after.
if [ -n "${REPLAY_SIGN_IDENTITY:-}" ]; then
    codesign --force --deep --options runtime --timestamp \
        --sign "$REPLAY_SIGN_IDENTITY" "$APP" \
      && echo "Signed with $REPLAY_SIGN_IDENTITY (hardened runtime)." \
      || { echo "signing failed with $REPLAY_SIGN_IDENTITY" >&2; exit 1; }
else
    codesign --force --sign - "$APP" >/dev/null 2>&1 \
      && echo "Signed ad-hoc — runs here, and nowhere else." \
      || echo "Could not sign; the app may still run locally."
fi

echo "Built $APP"
echo "Run with: open '$APP'   (or '$APP/Contents/MacOS/Replay' to see stdout)"
