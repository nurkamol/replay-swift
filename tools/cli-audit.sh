#!/usr/bin/env bash
#
# Check that `replay` answers, and answers the way a script would expect.
#
# The other audits in this directory check the app against itself — no view spells a
# constant, no key is bound and undocumented. This one checks the only surface with a
# contract that is not a screen: exit codes, stream discipline, and the shape of `--json`.
#
# Those three are the whole reason a CLI is different from a function. A script branches on
# the exit code, pipes stdout somewhere, and parses the JSON — so getting any of them wrong
# breaks somebody's automation silently while every sentence still reads correctly by eye.
#
#   ./tools/cli-audit.sh
#
set -uo pipefail
cd "$(dirname "$0")/.."

BIN="$(swift build --show-bin-path 2>/dev/null)/replay"
[ -x "$BIN" ] || { echo "cli audit: no binary — run 'swift build' first" >&2; exit 1; }

pass=0
fail=0

check() { # description, expected-exit, command…
  local what="$1" want="$2"; shift 2
  "$@" >/dev/null 2>&1
  local got=$?
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "  ✗ $what — exit $got, wanted $want" >&2
  fi
}

# ── asking wrongly is exit 1, and is never confused with having no answer ─────
check "an unknown command"            1 "$BIN" wat
check "a date it cannot read"         1 "$BIN" day nonsense
check "an unknown export format"      1 "$BIN" export --format xlsx
# PDF is a *known* format the CLI cannot produce: it is drawn by SwiftUI, and a command-line
# tool has no way to render one. It has to be refused rather than silently written as
# Markdown into a file named .pdf — which is what happened the moment the format was added.
check "a format the CLI cannot draw"  1 "$BIN" export --format pdf
check "an unknown export scope"       1 "$BIN" export --scope decade
check "a day with no date"            1 "$BIN" day
check "an app with no name"           1 "$BIN" app

# ── a missing record is exit 2: a fact about the data, not a bug in the script ─
check "a database that is not there"  2 "$BIN" today --database /nonexistent/activity.db

# ── the things that must work with no database at all ─────────────────────────
check "help"                          0 "$BIN" help
check "--version"                     0 "$BIN" --version

# ── stream discipline, checked only where there is a record to read ───────────
if [ -f "$HOME/Library/Application Support/app.replay.native/activity.db" ]; then
  check "today"                       0 "$BIN" today
  check "today as JSON"               0 "$BIN" today --json

  # `--json` has to be parseable, or it is a sentence with braces around it.
  if ! "$BIN" today --json | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    fail=$((fail + 1)); echo "  ✗ --json did not parse as JSON" >&2
  else
    pass=$((pass + 1))
  fi

  # Every command answers with the same keys around it, so a script can rely on one shape.
  for key in sentence day; do
    if ! "$BIN" today --json | grep -q "\"$key\""; then
      fail=$((fail + 1)); echo "  ✗ --json is missing \"$key\"" >&2
    else
      pass=$((pass + 1))
    fi
  done

  # The one that would ruin a pipeline: progress on stdout instead of stderr.
  tmp="$(mktemp)"
  "$BIN" export --format csv --scope today --output "$tmp" >"$tmp.out" 2>/dev/null
  if [ -s "$tmp.out" ]; then
    fail=$((fail + 1)); echo "  ✗ --output wrote progress to stdout, not stderr" >&2
  else
    pass=$((pass + 1))
  fi
  rm -f "$tmp" "$tmp.out"

  # And a report on stdout has to be the report, with nothing bolted on.
  if [ "$("$BIN" export --format csv --scope today | head -1)" != \
       "Date,Start,End,Duration,Category,Title,Applications,Tags,Bookmarked,Note" ]; then
    fail=$((fail + 1)); echo "  ✗ a piped CSV export did not begin with its header row" >&2
  else
    pass=$((pass + 1))
  fi
else
  echo "cli audit: no local record — checked argument handling only."
fi

if [ "$fail" -gt 0 ]; then
  echo "cli audit: $fail of $((pass + fail)) checks failed." >&2
  exit 1
fi
echo "cli audit: $pass checks — exit codes, streams and the JSON shape all hold."
