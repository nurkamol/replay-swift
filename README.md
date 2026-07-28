# Replay — native macOS

A native Swift port of Replay, a private timeline of the apps you use. Everything stays
on the Mac: no cloud, no account, no network code, and no permissions requested.

The [Glaze version](https://github.com/nurkamol/replay-glaze) ships today and is the
reference implementation — [get it on the Glaze Store](https://www.glaze.app/app/replay-4fgahp).
This repo trails it deliberately, with a generated contract between them so it cannot trail
it *silently*.

## Install

There is no download yet, and that is deliberate rather than unfinished.

```bash
git clone https://github.com/nurkamol/replay-swift.git
cd replay-swift
./scripts/make-app.sh release      # builds and assembles Replay.app
open build/Replay.app
```

**Why building it is currently the *better* route, not the fallback.** An app built here is
signed ad-hoc and was never downloaded, so it has no quarantine flag and opens immediately.
A disk image from a release page would not: without a Developer ID signature Gatekeeper
rejects it outright — measured, not assumed, in [docs/FINDINGS.md](docs/FINDINGS.md) — and
since macOS 15 there is no Control-click bypass, so the only way in is System Settings ▸
Privacy & Security ▸ Open Anyway.

Which is a poor thing to ask of anybody, and a worse thing to ask for *this* app. Replay's
whole claim is that nothing leaves your Mac and nothing is being asked of you. Telling you to
override macOS's own security check in order to install it would undercut the only thing it
is really selling.

`scripts/make-dmg.sh` and `.github/workflows/release.yml` are written and waiting; the day a
Developer ID exists, a signed and notarised image is one tag away.

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
Checking this port against Glaze 2.3.2 (d355ba2)

✓ constants — 226 checks
✓ narrative copy — 34 checks
✓ category table — 7 checks
✓ schema — 1 checks
✓ store round-trip — 7 checks
✓ annotations — 15 checks
✓ maintenance — 12 checks
✓ session derivation
   ✓ one-session-two-apps — Consecutive rows with no gap form a single session…
   ✓ away-row-splits-session — A measured idle row is a break, and splits the run…
   … 8 scenarios …

PARITY OK — 931 checks against Glaze 2.3.2
```

## What is here

```
Sources/ReplayCore/
  Model.swift            events, sessions, summaries, Rules (the thresholds)
  ActivityStore.swift    SQLite: storage, headlines, deletion, compaction
  SessionBuilder.swift   the derivation — rows → named sessions and breaks
  ActivityTracker.swift  NSWorkspace + idle time → recorded sessions
Sources/ParityKit/       the parity suite — 931 checks against the reference
Sources/ReplayParity/    `swift run replay-parity` — the same suite without Xcode
Sources/ReplayCLI/       `replay` — the record from a shell, needing no Developer ID
Sources/ReplayApp/       the application — every surface, and DesignSystem.swift
Tests/ReplayCoreTests/   `swift test` — the same suite via swift-testing
Tests/ReplayAppTests/    61 behaviour cases over the app's own models
spec/                    GENERATED contract — never hand-edit
tools/sync-spec.mjs      regenerates spec/ from the Glaze sources
tools/port-queue.mjs     lists Glaze commits this port still owes
tools/design-audit.mjs   fails if a view spells a visual constant
tools/shortcut-audit.mjs fails if a bound key is undocumented, or documented and unbound
tools/cli-audit.sh       the CLI's exit codes, stream discipline and --json shape
Resources/AppIcon.icns   the product's icon, carried over from the Glaze app
docs/                    read these
scripts/make-app.sh      assemble a runnable .app
scripts/make-dmg.sh      a disk image; --release signs, notarises and staples it
scripts/icon-probe.sh    the sandbox experiment behind docs/FINDINGS.md
```

**Feature-complete at 0.9.0.** Every route the reference has, both of its display modes —
the screensaver and ambient mode — and the whole of its Settings. The core was finished and
verified early; the interface was the bulk of the work, as
[docs/PORTING-MAP.md](docs/PORTING-MAP.md) predicted it would be.

Nine rather than ten because it still cannot be installed by anyone but the person who
built it: `scripts/make-app.sh` signs ad-hoc, and a Developer ID is the only thing between
that and a build you could hand to somebody. What is left is in
[docs/BACKLOG.md](docs/BACKLOG.md), which is short and mostly not code.

**A caveat worth reading before trusting the number.** 931 checks cover the core and the
values behind the interface, and nothing exercises the interface itself. Three bugs in this
release were invisible to every automated check and were found by looking at the app: a
Settings toggle bound to the wrong `Bool`, chrome laid out off-screen, and a test suite
leaking a `UserDefaults` domain per fixture. A high check count is evidence about what it
covers, not about what it does not.

## Documentation

| | |
|---|---|
| [docs/SPEC.md](docs/SPEC.md) | **what Replay does** — the invariants a port gets wrong at the design level |
| [docs/SYNC.md](docs/SYNC.md) | **how the two stay honest** — the generated contract and the loop |
| [docs/PORTING-MAP.md](docs/PORTING-MAP.md) | every Glaze API → native equivalent, costs, and the two real risks |
| [docs/PARITY.md](docs/PARITY.md) | feature-by-feature status ledger, and every known divergence |
| [docs/BACKLOG.md](docs/BACKLOG.md) | **the only list of remaining work** — parity, decisions, and §6 for ideas of this port's own |
| [docs/FINDINGS.md](docs/FINDINGS.md) | questions that decided something, with the evidence |
| [plans/](plans/) | animation audit findings and the plans they became |
| [docs/GLAZE-CHANGELOG.md](docs/GLAZE-CHANGELOG.md) | the reference implementation's release history (a copy) |
| [docs/ROADMAP.md](docs/ROADMAP.md) | retired — kept as history; the backlog supersedes it |

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

The tooling reads the Glaze app's source from a local Glaze install — it defaults to
`~/Library/Application Support/app.glaze.macos.main/apps/replay-local-25gyn8jy/.glaze-sources`
and can be pointed elsewhere with `GLAZE_SRC=…`. The same source is published at
[nurkamol/replay-glaze](https://github.com/nurkamol/replay-glaze), though note a bare clone
of it cannot be built without a Glaze install.

## Toolchain

**Xcode 27 beta** (`/Applications/Xcode-beta.app`, Swift 6.4) — set `DEVELOPER_DIR` as
above, or select it with `xcode-select`. That gives `swift test`, a real test target, and
the notarisation and App Store paths.

Command Line Tools alone (Swift 6.2.3) still builds everything and runs
`swift run replay-parity`; only `swift test` needs Xcode. See the toolchain section of
[docs/PORTING-MAP.md](docs/PORTING-MAP.md).

No external dependencies, on purpose: SQLite from the system, AppKit for the tracker,
SwiftUI for the UI. Nothing to resolve, nothing to vendor.

## Licence

[MIT](LICENSE) — Copyright © 2026 Nurkamol Vakhidov.

Note the Glaze implementation is Apache 2.0 rather than MIT. Both are mine to license, so
the split is deliberate: this port is the more permissive of the two. MIT grants no
trademark rights either way — "Replay" is the product's name, not part of what is licensed,
so please don't ship a fork calling itself Replay.
