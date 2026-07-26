# Replay — native macOS

A native Swift port of Replay, a private timeline of the apps you use. Everything stays
on the Mac: no cloud, no account, no network code, and no permissions requested.

The [Glaze version](#relationship-to-the-glaze-app) ships today and is the reference
implementation. This repo trails it deliberately, with a generated contract between them
so it cannot trail it *silently*.

## Quickstart

```bash
cd ~/coding/replay

swift build                     # ReplayCore + the parity suite
node tools/sync-spec.mjs        # re-read the Glaze sources into spec/
swift test                      # the parity suite, via swift-testing
```

`swift test` needs Xcode pointed out, because Xcode 27 beta is installed but is not the
selected developer directory:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```

Put that in your shell profile, or run `sudo xcode-select -s /Applications/Xcode-beta.app`
once to make it the default. Without it, use the same suite as an executable — it needs
no Xcode at all:

```bash
swift run replay-parity
```

Expected, when the two agree:

```
Checking this port against Glaze 2.3.1 (9dcd1bb)

✓ constants — 11 checks
✓ category table — 7 checks
✓ schema — 1 checks
✓ session derivation
   ✓ one-session-two-apps — Consecutive rows with no gap form a single session…
   ✓ away-row-splits-session — A measured idle row is a break, and splits the run…
   … 8 scenarios …
✓ store round-trip — 7 checks

PARITY OK — 188 checks against Glaze 2.3.1
```

## What is here

```
Sources/ReplayCore/
  Model.swift            events, sessions, summaries, Rules (the thresholds)
  ActivityStore.swift    SQLite: storage, headlines, deletion, compaction
  SessionBuilder.swift   the derivation — rows → named sessions and breaks
  ActivityTracker.swift  NSWorkspace + idle time → recorded sessions
Sources/ParityKit/       the parity suite — 188 checks against the reference
Sources/ReplayParity/    `swift run replay-parity` — the same suite without Xcode
Sources/ReplayApp/       placeholder; the UI is not started
Tests/ReplayCoreTests/   `swift test` — the same suite via swift-testing
spec/                    GENERATED contract — never hand-edit
tools/sync-spec.mjs      regenerates spec/ from the Glaze sources
docs/                    read these
scripts/make-app.sh      assemble a runnable .app
scripts/icon-probe.sh    the sandbox experiment behind docs/FINDINGS.md
```

**The core is done and verified.** Storage, session derivation, and the tracker are
ported and checked against the reference implementation. The UI has not been started —
that is the bulk of the work, and [docs/PORTING-MAP.md](docs/PORTING-MAP.md) scopes it.

## Documentation

| | |
|---|---|
| [docs/SPEC.md](docs/SPEC.md) | **what Replay does** — the invariants a port gets wrong at the design level |
| [docs/SYNC.md](docs/SYNC.md) | **how the two stay honest** — the generated contract and the loop |
| [docs/PORTING-MAP.md](docs/PORTING-MAP.md) | every Glaze API → native equivalent, costs, and the two real risks |
| [docs/PARITY.md](docs/PARITY.md) | feature-by-feature status ledger |
| [docs/FINDINGS.md](docs/FINDINGS.md) | questions that decided something, with the evidence |

Read SPEC.md before writing any feature code. The constants are checked automatically;
the invariants in that file are the ones that will bite.

## Relationship to the Glaze app

Every change lands in the Glaze app **first**, then here:

```
edit Glaze  →  node tools/sync-spec.mjs  →  git diff spec/  →  port  →  swift run replay-parity
                                              ↑
                                    this diff is the work
```

`spec/` is generated from the Glaze sources by reading its code and *running* its session
derivation — so `spec/fixtures/` holds not a description of the expected output but the
output the shipping implementation actually produced. A clean `git diff spec/` after
regenerating means there is nothing to port. See [docs/SYNC.md](docs/SYNC.md).

Glaze sources default to
`~/Library/Application Support/app.glaze.macos.main/apps/replay-local-25gyn8jy/.glaze-sources`;
override with `GLAZE_SRC=…`.

## Toolchain

**Xcode 27 beta** (`/Applications/Xcode-beta.app`, Swift 6.4) — set `DEVELOPER_DIR` as
above, or select it with `xcode-select`. That gives `swift test`, a real test target, and
the notarisation and App Store paths.

Command Line Tools alone (Swift 6.2.3) still builds everything and runs
`swift run replay-parity`; only `swift test` needs Xcode. See the toolchain section of
[docs/PORTING-MAP.md](docs/PORTING-MAP.md).

No external dependencies, on purpose: SQLite from the system, AppKit for the tracker,
SwiftUI for the UI. Nothing to resolve, nothing to vendor.
