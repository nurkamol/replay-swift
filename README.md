# Replay — native macOS

A native Swift port of Replay, a private timeline of the apps you use. Everything stays
on the Mac: no cloud, no account, no network code, and no permissions requested.

The [Glaze version](#relationship-to-the-glaze-app) ships today and is the reference
implementation. This repo trails it deliberately, with a generated contract between them
so it cannot trail it *silently*.

## Quickstart

```bash
cd ~/coding/replay

swift build                     # builds ReplayCore + the parity checker
node tools/sync-spec.mjs        # re-read the Glaze sources into spec/
swift run replay-parity         # check this port against them
```

Expected, when the two agree:

```
Checking this port against Glaze 2.3.1 (9dcd1bb)
── constants
── category table (order matters — first match wins, and it names the session)
── schema
── session derivation
   ✓ one-session-two-apps — Consecutive rows with no gap form a single session…
   ✓ away-row-splits-session — A measured idle row is a break, and splits the run…
   … 8 scenarios …
── store round-trip

PARITY OK — 188 checks against Glaze 2.3.1
```

## What is here

```
Sources/ReplayCore/
  Model.swift            events, sessions, summaries, Rules (the thresholds)
  ActivityStore.swift    SQLite: storage, headlines, deletion, compaction
  SessionBuilder.swift   the derivation — rows → named sessions and breaks
  ActivityTracker.swift  NSWorkspace + idle time → recorded sessions
Sources/ReplayParity/    `swift run replay-parity` — measures this port against Glaze
Sources/ReplayApp/       placeholder; the UI is not started
spec/                    GENERATED contract — never hand-edit
tools/sync-spec.mjs      regenerates spec/ from the Glaze sources
docs/                    read these
scripts/make-app.sh      assemble a runnable .app without Xcode
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

Swift 6.2.3 via Command Line Tools is enough to build and verify everything here. Full
Xcode is needed for `XCTest`/`swift-testing`, a `.xcodeproj`, notarisation, and any App
Store submission — see the toolchain section of
[docs/PORTING-MAP.md](docs/PORTING-MAP.md).

No external dependencies, on purpose: SQLite from the system, AppKit for the tracker,
SwiftUI for the UI. Nothing to resolve, nothing to vendor.
