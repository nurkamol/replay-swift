#!/bin/bash
# Does app-icon fetching survive App Sandbox?
#
# Builds one binary, wraps it in two .app bundles, and signs the second with
# com.apple.security.app-sandbox — then runs both and compares. See
# Sources/IconProbe/main.swift for why the comparison is by pixel hash rather than by
# success/failure: icon(forFile:) returns a generic placeholder rather than failing.
#
#   ./scripts/icon-probe.sh
#
# Requires nothing but Command Line Tools. Ad-hoc signing is enough — the sandbox engages
# from the entitlement, not from the identity.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/icon-probe"
rm -rf "$OUT"
mkdir -p "$OUT"

echo "Building…"
swift build --package-path "$ROOT" >/dev/null
# SPM names the binary after the *product*, not the target — so `icon-probe`.
BIN="$(swift build --package-path "$ROOT" --show-bin-path)/icon-probe"
[ -x "$BIN" ] || { echo "no binary at $BIN" >&2; exit 1; }

# ── bundle ────────────────────────────────────────────────────────────────────
# The sandbox only applies to a real bundle launched through LaunchServices; running the
# bare binary would silently test nothing.
make_bundle() {
    # Separate statements: `local a=$1 b=$a` expands $a before it is assigned, which
    # trips `set -u`.
    local name="$1"
    local bundle_id="$2"
    local app="$OUT/$name.app"
    mkdir -p "$app/Contents/MacOS"
    cp "$BIN" "$app/Contents/MacOS/$name"
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>          <string>$name</string>
  <key>CFBundleIdentifier</key>    <string>$bundle_id</string>
  <key>CFBundleExecutable</key>    <string>$name</string>
  <key>CFBundlePackageType</key>   <string>APPL</string>
  <key>CFBundleVersion</key>       <string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key>           <true/>
</dict>
</plist>
PLIST
    echo "$app"
}

PLAIN_APP="$(make_bundle IconProbePlain app.replay.iconprobe.plain)"
SANDBOX_APP="$(make_bundle IconProbeSandboxed app.replay.iconprobe.sandboxed)"

cat > "$OUT/sandbox.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <!-- Deliberately the strictest case: the sandbox and nothing else. No file access, no
       temporary exceptions. If icons work here they work in any configuration. -->
  <key>com.apple.security.app-sandbox</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$PLAIN_APP" 2>/dev/null
codesign --force --sign - --entitlements "$OUT/sandbox.entitlements" "$SANDBOX_APP" 2>/dev/null
echo "Signed. Sandbox entitlement on the second bundle:"
codesign -d --entitlements - "$SANDBOX_APP" 2>&1 | grep -o 'app-sandbox' | head -1 | sed 's/^/  /'

# ── run ───────────────────────────────────────────────────────────────────────
# A sandboxed process can only write inside its own container, so that is where its report
# goes; the path is predictable, which is what makes this scriptable.
PLAIN_OUT="$OUT/plain.json"
SANDBOX_CONTAINER="$HOME/Library/Containers/app.replay.iconprobe.sandboxed/Data"
SANDBOX_OUT="$SANDBOX_CONTAINER/Documents/report.json"

echo "Running unsandboxed…"
open -W -a "$PLAIN_APP" --args "$PLAIN_OUT"

echo "Running sandboxed…"
mkdir -p "$SANDBOX_CONTAINER/Documents" 2>/dev/null || true
open -W -a "$SANDBOX_APP" --args "$SANDBOX_OUT"
sleep 1

[ -f "$PLAIN_OUT" ]   || { echo "the unsandboxed run wrote nothing" >&2; exit 1; }
[ -f "$SANDBOX_OUT" ] || { echo "the sandboxed run wrote nothing to $SANDBOX_OUT" >&2; exit 1; }
cp "$SANDBOX_OUT" "$OUT/sandboxed.json"

# ── compare ───────────────────────────────────────────────────────────────────
python3 - "$PLAIN_OUT" "$OUT/sandboxed.json" <<'PY'
import json, sys

plain = json.load(open(sys.argv[1]))
sand  = json.load(open(sys.argv[2]))

print()
print("=" * 78)
print(f"{'':28} {'unsandboxed':>14}  {'sandboxed':>14}")
print("-" * 78)
print(f"{'sandbox actually engaged':28} {str(plain['sandboxed']):>14}  {str(sand['sandboxed']):>14}")
print(f"{'home / container':28}")
print(f"  plain:     {plain['containerPath']}")
print(f"  sandboxed: {sand['containerPath']}")
print()

by_id = {r["bundleID"]: r for r in sand["results"]}
generic_plain = plain["extras"].get("genericIconHash")
generic_sand  = sand["extras"].get("genericIconHash")

installed = matched = differed = generic = missing_path = 0
rows = []
for p in plain["results"]:
    s = by_id.get(p["bundleID"], {})
    if not p.get("resolvedPath"):
        continue                      # not installed; nothing to compare
    installed += 1
    if not s.get("resolvedPath"):
        missing_path += 1
        rows.append((p["bundleID"], "path NOT resolved in sandbox"))
        continue
    ph, sh = p.get("iconHash"), s.get("iconHash")
    if sh and sh == generic_sand:
        generic += 1
        rows.append((p["bundleID"], "GENERIC placeholder in sandbox"))
    elif ph and sh and ph == sh:
        matched += 1
        rows.append((p["bundleID"], f"identical  {sh[:16]}…  {s.get('pngBytes')}B"))
    else:
        differed += 1
        rows.append((p["bundleID"], f"DIFFERS  plain={str(ph)[:12]}… sandboxed={str(sh)[:12]}…"))

for name, note in rows:
    mark = "✓" if note.startswith("identical") else "✗"
    print(f"  {mark} {name:34} {note}")

# Distinct hashes within the sandboxed run: if every app collapses to one hash, that is a
# single generic icon reused, whatever the individual comparisons say.
sand_hashes = {r["iconHash"] for r in sand["results"] if r.get("iconHash")}
print()
print(f"installed apps compared     {installed}")
print(f"  icons identical           {matched}")
print(f"  generic placeholder       {generic}")
print(f"  differing hash            {differed}")
print(f"  path unresolved           {missing_path}")
print(f"distinct icons in sandbox   {len(sand_hashes)}  (1 would mean a single fallback)")
print()
for key in sorted(set(plain["extras"]) | set(sand["extras"])):
    print(f"  {key:26} plain={plain['extras'].get(key)!s:<34} sandboxed={sand['extras'].get(key)}")

print()
print("=" * 78)
if not sand["sandboxed"]:
    print("INCONCLUSIVE — the second run was not sandboxed; the entitlement did not take.")
    sys.exit(2)
if installed and matched == installed:
    print("RESULT: app icons work under App Sandbox, byte-identical. No entitlement needed.")
    sys.exit(0)
if matched:
    print(f"RESULT: PARTIAL — {matched} of {installed} icons survived. Read the rows above.")
    sys.exit(1)
print("RESULT: app icons are BLOCKED by App Sandbox. A fallback or exception is required.")
sys.exit(1)
PY
