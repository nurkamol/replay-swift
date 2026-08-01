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

mkdir -p "$OUT"
sed "s|@ROOT@|$ROOT|g" "$TEMPLATE" > "$OUT/Replay (bundle).xcscheme"

# It has to be well-formed XML. Xcode's own parser is lenient enough to list a scheme with a
# malformed comment in it — which it did, and the file was invalid — so this asks something
# stricter before saying it worked.
python3 -c "import xml.etree.ElementTree as ET, sys; ET.parse(sys.argv[1])" \
    "$OUT/Replay (bundle).xcscheme"

echo "Wrote 'Replay (bundle)' scheme → ${OUT#"$ROOT"/}"
echo "  Reopen the package in Xcode (xed .) and pick it from the scheme menu."
echo "  ⌘R assembles build/Replay.app and launches that, rather than the bare binary."
