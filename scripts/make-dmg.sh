#!/bin/bash
# Wrap Replay.app in a disk image somebody could actually download.
#
#   ./scripts/make-dmg.sh              a disk image for testing, unsigned
#   ./scripts/make-dmg.sh --release    one that is signed, notarised and stapled
#
# **The two modes exist because a half-signed download is worse than none.** Without a
# Developer ID, Gatekeeper refuses a downloaded app outright and the person who tried reads
# it as a broken app rather than an unsigned one — you get one first impression. So the
# plain form builds an image and says plainly that it is for testing here; `--release`
# refuses to produce anything it cannot sign, notarise and staple.
#
# What `--release` needs, all from the environment:
#   REPLAY_SIGN_IDENTITY   "Developer ID Application: Name (TEAMID)"
#   REPLAY_NOTARY_PROFILE  a `notarytool store-credentials` profile name
#     …or REPLAY_NOTARY_KEY / REPLAY_NOTARY_KEY_ID / REPLAY_NOTARY_ISSUER for an API key,
#     which is what CI uses because it has no keychain worth storing a profile in.
#
# Nothing here is a substitute for `xcrun stapler validate`, which runs at the end and is
# the only step that proves the result opens on a machine that has never seen it.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Replay.app"
STAGE="$ROOT/build/dmg-stage"
VERSION="$(grep -m1 '^VERSION=' "$ROOT/scripts/make-app.sh" | cut -d'"' -f2)"
DMG="$ROOT/build/Replay-$VERSION.dmg"
VOLUME="Replay $VERSION"

RELEASE=0
[ "${1:-}" = "--release" ] && RELEASE=1

# ── refuse early, and say which piece is missing ──────────────────────────────
#
# Checked before anything is built, so a release that cannot be finished fails in a second
# rather than after a full build — and names the one variable that was absent.
if [ "$RELEASE" = 1 ]; then
    [ -n "${REPLAY_SIGN_IDENTITY:-}" ] || {
        echo "make-dmg: --release needs REPLAY_SIGN_IDENTITY (a Developer ID Application certificate)." >&2
        echo "          Without it the disk image would be refused by Gatekeeper on every other Mac." >&2
        exit 1
    }
    if [ -z "${REPLAY_NOTARY_PROFILE:-}" ] && [ -z "${REPLAY_NOTARY_KEY:-}" ]; then
        echo "make-dmg: --release needs REPLAY_NOTARY_PROFILE, or the REPLAY_NOTARY_KEY trio." >&2
        echo "          A signed but un-notarised image still warns on first open." >&2
        exit 1
    fi
fi

# ── the app ──────────────────────────────────────────────────────────────────
"$ROOT/scripts/make-app.sh" release

# ── the window somebody sees when they open it ───────────────────────────────
#
# An `/Applications` symlink beside the app and nothing else. No background image and no
# scripted window geometry: those need AppleScript against the Finder, which is flaky
# unattended and would make this the one build step that cannot run headless in CI.
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Replay.app"
ln -s /Applications "$STAGE/Applications"

echo "Building $(basename "$DMG")…"
hdiutil create \
    -volname "$VOLUME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO -quiet \
    "$DMG"
rm -rf "$STAGE"

# ── sign, notarise, staple ───────────────────────────────────────────────────
if [ "$RELEASE" = 1 ]; then
    # The image is signed too, not only the app inside it: Gatekeeper checks both, and an
    # unsigned container around a signed app still prompts.
    codesign --force --sign "$REPLAY_SIGN_IDENTITY" --timestamp "$DMG"
    echo "Signed the image."

    echo "Notarising — this waits on Apple, usually a minute or two…"
    if [ -n "${REPLAY_NOTARY_PROFILE:-}" ]; then
        xcrun notarytool submit "$DMG" --keychain-profile "$REPLAY_NOTARY_PROFILE" --wait
    else
        xcrun notarytool submit "$DMG" \
            --key "$REPLAY_NOTARY_KEY" \
            --key-id "$REPLAY_NOTARY_KEY_ID" \
            --issuer "$REPLAY_NOTARY_ISSUER" \
            --wait
    fi

    # Stapling is what lets it open with no network. Without it a first launch on a machine
    # that is offline, or behind a captive portal, fails in a way nobody can diagnose.
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    echo "Notarised and stapled."
else
    echo
    echo "  This image is for testing on this Mac. It is not signed with a Developer ID,"
    echo "  so Gatekeeper will refuse it anywhere else. Use --release to make a real one."
fi

# A checksum beside the file, so a download can be verified against the release page.
shasum -a 256 "$DMG" | awk '{print $1}' > "$DMG.sha256"

echo
echo "Built $DMG"
echo "  $(du -h "$DMG" | cut -f1)  ·  sha256 $(cat "$DMG.sha256")"
