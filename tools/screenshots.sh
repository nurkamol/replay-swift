#!/bin/bash
#
# Every surface, captured, in one command.
#
#   ./tools/screenshots.sh                       # to build/screenshots/
#   ./tools/screenshots.sh out/somewhere         # somewhere else
#   ./tools/screenshots.sh --width 1600          # a wider window
#   ./tools/screenshots.sh --appearance light    # the theme nobody has ever audited
#   ./tools/screenshots.sh --keep-open           # leave the app running afterwards
#
# Why this exists
# ---------------
# The parity suite is 951 checks and the behaviour suite is 90, and between them they have
# never caught a layout bug — not one. In a single day this port shipped and then fixed: a
# banner covering the day's headline, a banner pushing the sidebar off the top of the window,
# a notes popover as a fixed box of raw Markdown, a dead column against the scroll bar on any
# wide window, prose running a hundred and fifty characters to a line, a lightbox caption that
# rendered nowhere, and a row of five buttons at five different weights. Every one was found by
# rendering it and looking at it, and every one was invisible to a test.
#
# So the bottleneck was never "should we check the interface" — it was that looking cost a
# dozen commands of window arithmetic each time. This makes it one.
#
# It is deliberately not a UI *test*: there are no assertions here, and there is no attempt to
# decide whether a screen is right. `XCUITest` can tell you a button exists and is hittable,
# which is not the question — "does this read badly" is, and a person answers it in a second
# from an image. This produces the images.
#
# How it drives the app
# ---------------------
# Keyboard only, through the app's own two ways of going somewhere by name: the numbered
# shortcuts (⌘1–⌘9, checked by `tools/shortcut-audit.mjs`) and the command palette. Both are
# real user paths, so the harness exercises them rather than working around them.
#
# **Not by clicking the sidebar.** That was tried first and does not work: AppKit reports the
# row under the pointer, `AXPress` returns success, and the selection does not change — SwiftUI
# list rows do not expose a usable action. Four attempts and a stray keypress that flipped the
# user's theme went into learning that. Every coordinate in this script is a window frame read
# from the accessibility API, never a guess at where something is drawn.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/Replay.app"

OUT="$ROOT/build/screenshots"
KEEP_OPEN=0
WIDTH=1280
APPEARANCE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --keep-open)  KEEP_OPEN=1 ;;
        --width)      WIDTH="$2"; shift ;;
        --appearance) APPEARANCE="$2"; shift ;;
        -*) echo "screenshots: unknown option $1" >&2; exit 2 ;;
        *)  OUT="$1" ;;
    esac
    shift
done

# The theme is a *preference*, which means overriding it writes to the user's own defaults.
# Saved and put back on any exit — including a failure or a Control-C — because a harness that
# leaves somebody's Mac in dark mode is worse than one that cannot test light mode. (This is
# not hypothetical: an earlier stray keypress flipped it and it took a `defaults write` to
# notice and undo.)
DOMAIN="app.replay.native"
PREVIOUS_APPEARANCE=""
HAD_APPEARANCE=0
restore_appearance () {
    [ -n "$APPEARANCE" ] || return 0
    if [ "$HAD_APPEARANCE" = "1" ]; then
        defaults write "$DOMAIN" appearance -string "$PREVIOUS_APPEARANCE"
    else
        defaults delete "$DOMAIN" appearance 2>/dev/null || true
    fi
}
trap restore_appearance EXIT INT TERM

if [ ! -d "$APP" ]; then
    echo "screenshots: no build at $APP — run ./scripts/make-app.sh first." >&2
    exit 1
fi

mkdir -p "$OUT"
rm -f "$OUT"/*.png

# One size for every capture, so two runs are comparable and a layout that only breaks wide
# is not hidden by whatever size the window happened to be left at.
HEIGHT=860
POS_X=80
POS_Y=80

say () { printf '  %-14s %s\n' "$1" "$2"; }

osa () { /usr/bin/osascript "$@"; }

# The window's real frame, from the accessibility API. Everything else here depends on this
# being measured rather than assumed.
window_rect () {
    osa -e 'tell application "System Events" to tell process "Replay"
              set p to position of window 1
              set s to size of window 1
              return ((item 1 of p) as string) & "," & ((item 2 of p) as string) & "," & ¬
                     ((item 1 of s) as string) & "," & ((item 2 of s) as string)
            end tell' 2>/dev/null | tr -d ' '
}

capture () {  # capture <name>
    local rect
    rect="$(window_rect)"
    if [ -z "$rect" ]; then
        say "$1" "SKIPPED — no window"
        return
    fi
    /usr/sbin/screencapture -o -x -R "$rect" "$OUT/$1.png"
    say "$1" "$(basename "$OUT/$1.png")"
}

# ── Launch ────────────────────────────────────────────────────────────────────

if [ -n "$APPEARANCE" ]; then
    if PREVIOUS_APPEARANCE="$(defaults read "$DOMAIN" appearance 2>/dev/null)"; then
        HAD_APPEARANCE=1
    fi
    defaults write "$DOMAIN" appearance -string "$APPEARANCE"
fi

pkill -f "$APP" 2>/dev/null || true
sleep 1
open -a "$APP"
sleep 8

osa -e 'tell application "Replay" to activate' >/dev/null
sleep 1
osa -e "tell application \"System Events\" to tell process \"Replay\"
          set position of window 1 to {$POS_X, $POS_Y}
          set size of window 1 to {$WIDTH, $HEIGHT}
        end tell" >/dev/null
sleep 2

echo "Capturing ${WIDTH}x${HEIGHT}${APPEARANCE:+ (${APPEARANCE})} into ${OUT#$ROOT/}"

# ── The nine with a shortcut ──────────────────────────────────────────────────
#
# Parallel arrays rather than a map: macOS ships bash 3.2, which has no associative arrays,
# and this script is not worth a dependency on a newer shell.

NAMES="today search week timeline apps projects collections memories story"
KEYS="1 2 3 4 5 6 7 8 9"

set -- $KEYS
for name in $NAMES; do
    key="$1"; shift
    osa -e 'tell application "Replay" to activate' \
        -e "tell application \"System Events\" to keystroke \"$key\" using command down" >/dev/null
    # Long enough for a surface that loads from the database and then animates in. Canvas is
    # the slowest and gets its own wait below.
    sleep 4
    capture "$name"
done

# Going somewhere by name.
#
# The delays are generous because the palette's field takes focus *asynchronously*: type too
# soon and the keystrokes go nowhere, the query stays empty, and Return opens whatever happened
# to be first in an unfiltered list of fifty-two. That is not hypothetical — it is how the
# first light-mode run captured the desktop twice instead of the two display modes, and the
# only evidence was "52 results" in the corner of a screenshot.
palette_go () {  # palette_go <query>
    osa -e 'tell application "System Events" to key code 53' >/dev/null 2>&1 || true
    sleep 0.5
    osa -e 'tell application "Replay" to activate' -e 'delay 0.6' \
        -e 'tell application "System Events" to keystroke "k" using command down' >/dev/null
    sleep 2
    osa -e "tell application \"System Events\" to keystroke \"$1\"" >/dev/null
    sleep 2
    osa -e 'tell application "System Events" to key code 36' >/dev/null
}

# ── Canvas, which has no shortcut ─────────────────────────────────────────────

palette_go "Canvas"
# The field is a force simulation seeded from each node's id — it settles, and a capture taken
# too early is of a graph mid-flight.
sleep 8
capture "canvas"

# ── Search, with something in it ──────────────────────────────────────────────
#
# ⌘F rather than clicking the field: clicking it does not give it focus, so typing went
# nowhere and the capture was of an empty state twice before this was worked out.

osa -e 'tell application "Replay" to activate' -e 'delay 0.4' \
    -e 'tell application "System Events" to keystroke "2" using command down' -e 'delay 2' \
    -e 'tell application "System Events" to keystroke "f" using command down' -e 'delay 1' \
    -e 'tell application "System Events" to keystroke "research"' >/dev/null
sleep 4
capture "search-results"

# ── Settings, which is its own window ─────────────────────────────────────────

osa -e 'tell application "Replay" to activate' -e 'delay 0.4' \
    -e 'tell application "System Events" to keystroke "," using command down' >/dev/null
sleep 4
capture "settings"
# Close it, so the frame reader goes back to the main window.
osa -e 'tell application "System Events" to tell process "Replay" to click button 1 of window 1' \
    >/dev/null 2>&1 || true
sleep 2

# ── The two full-screen modes ─────────────────────────────────────────────────
#
# Whole-display captures, because that is what they are. Esc closes both, and the script
# presses it whatever happens so a failed run cannot leave the screen taken over.

# Did a display mode actually take over? Its window is the size of the screen; the main
# window is the size this script set. Anything much wider than that is the mode.
in_display_mode () {
    local w
    # Assigned to a variable first, then indexed. `item 1 of (size of window 1)` inline is
    # parsed by AppleScript as indexing *every* window's size and errors — which the first
    # version did, silently, so every check returned false and two working captures were
    # reported as failures. Same shape as `window_rect` above, which is why that one works.
    w="$(osa -e 'tell application "System Events" to tell process "Replay"
                   set s to size of window 1
                   return (item 1 of s) as string
                 end tell' 2>/dev/null | tr -d ' ')"
    [ -n "$w" ] && [ "$w" -gt $((WIDTH + 300)) ]
}

for mode in "Ambient Mode:ambient" "Screensaver:screensaver"; do
    label="${mode%%:*}"
    file="${mode##*:}"
    ok=0
    # Three times, because the failure is a focus race in the palette and each attempt is
    # independent. Better a slow harness than one that quietly captures the desktop and calls
    # it ambient mode — which is exactly what it did before it learned to check.
    for attempt in 1 2 3; do
        palette_go "$label"
        sleep 6
        if in_display_mode; then ok=1; break; fi
        say "$file" "attempt $attempt did not enter the mode — retrying"
        osa -e 'tell application "System Events" to key code 53' >/dev/null 2>&1 || true
        sleep 2
    done
    if [ "$ok" = "1" ]; then
        /usr/sbin/screencapture -o -x "$OUT/$file.png"
        say "$file" "$(basename "$OUT/$file.png") (full screen)"
    else
        say "$file" "FAILED — never entered the mode, no capture written"
    fi
    osa -e 'tell application "System Events" to key code 53' >/dev/null 2>&1 || true
    sleep 2
done

# ── A contact sheet, if the machine can make one ──────────────────────────────
#
# Optional on purpose. The captures are the product; this is a convenience, and a repo with
# no runtime dependencies should not grow a hard one for a nicety.

if python3 -c "import PIL" 2>/dev/null; then
    python3 - "$OUT" <<'PY'
import sys, glob, os
from PIL import Image

out = sys.argv[1]
shots = sorted(p for p in glob.glob(os.path.join(out, "*.png"))
               if os.path.basename(p) != "contact-sheet.png")
if not shots:
    sys.exit(0)

cols = 4
tw, th = 420, 280
rows = (len(shots) + cols - 1) // cols
sheet = Image.new("RGB", (tw * cols, th * rows), (18, 18, 20))
for i, path in enumerate(shots):
    im = Image.open(path).convert("RGB")
    im.thumbnail((tw, th), Image.LANCZOS)
    x = (i % cols) * tw + (tw - im.width) // 2
    y = (i // cols) * th + (th - im.height) // 2
    sheet.paste(im, (x, y))
sheet.save(os.path.join(out, "contact-sheet.png"))
print(f"  {'contact sheet':<14} contact-sheet.png ({len(shots)} surfaces)")
PY
else
    echo "  (no PIL — skipping the contact sheet; the captures are all there)"
fi

# ── Leave the app as it was found ─────────────────────────────────────────────

if [ "$KEEP_OPEN" = "0" ]; then
    pkill -f "$APP" 2>/dev/null || true
else
    # Back to Today, so the harness does not leave you on whatever it looked at last.
    osa -e 'tell application "Replay" to activate' -e 'delay 0.4' \
        -e 'tell application "System Events" to keystroke "1" using command down' >/dev/null || true
fi

COUNT=$(ls -1 "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ')
echo "screenshots: $COUNT images in ${OUT#$ROOT/}"
