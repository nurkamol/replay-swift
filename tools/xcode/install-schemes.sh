#!/bin/bash
# Write the Xcode scheme that runs Replay as a real app bundle.
#
#   ./tools/xcode/install-schemes.sh
#
# Why this is generated rather than committed
# ===========================================
# The scheme has to name an absolute path, and an absolute path cannot be committed.
#
# Xcode launches an arbitrary bundle through `<PathRunnable FilePath="…">`, and that field
# takes no relative path and expands no build setting that exists here: `SRCROOT` is simply
# not defined for a SwiftPM package — verified with `xcodebuild -showBuildSettings`, which
# reports it nowhere, and with a scheme post-action, whose environment does not contain it
# either. So the path is baked in per machine, by this, in one command.
#
# The other scheme, `ReplayApp`, is committed and needs none of this: it runs the bare
# executable SwiftPM builds, which Xcode already knows how to find.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/.swiftpm/xcode/xcshareddata/xcschemes"
TEMPLATE="$ROOT/tools/xcode/Replay (bundle).xcscheme.in"

[ -f "$TEMPLATE" ] || { echo "missing $TEMPLATE" >&2; exit 1; }

# The project supersedes the scheme, so only one of them is ever written.
#
# Both solve the same problem — ⌘R running a real bundle instead of a bare executable — and
# offering both puts two entries in the scheme menu that differ only in how they get there.
# The project does it natively; the scheme does it with a build post-action because there was
# no project. Where XcodeGen exists, the scheme is redundant and is removed.
if command -v xcodegen >/dev/null 2>&1; then
    rm -f "$OUT/Replay (bundle).xcscheme"
else
    mkdir -p "$OUT"
    sed "s|@ROOT@|$ROOT|g" "$TEMPLATE" > "$OUT/Replay (bundle).xcscheme"

# It has to be well-formed XML. Xcode's own parser is lenient enough to list a scheme with a
# malformed comment in it — which it did, and the file was invalid — so this asks something
# stricter before saying it worked.
    python3 -c "import xml.etree.ElementTree as ET, sys; ET.parse(sys.argv[1])" \
        "$OUT/Replay (bundle).xcscheme"
fi

# The project, which is the better of the two routes: Xcode builds a real application
# target, so ⌘R needs no post-action, and App Intents metadata is generated natively rather
# than by the eighteen lines of flag-wrangling in make-app.sh.
#
# Optional, because XcodeGen is a tool somebody may not have and the package still opens
# without it — that is what the scheme above is for.
if command -v xcodegen >/dev/null 2>&1; then
    ( cd "$ROOT" && xcodegen generate --spec project.yml --quiet )
    echo "Generated Replay.xcodeproj from project.yml"
    echo "  Open that (not Package.swift) — ⌘R builds and runs the real app."
else
    echo "note: XcodeGen not installed, so Replay.xcodeproj was not generated."
    echo "      brew install xcodegen, then re-run this. Without it, open the package"
    echo "      itself and use the scheme below."
fi

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "Wrote 'Replay (bundle)' scheme → ${OUT#"$ROOT"/}"
    echo "  Open the package (xed .) and pick it from the scheme menu."
    echo "  ⌘R assembles build/Replay.app and launches that, rather than the bare binary."
fi
