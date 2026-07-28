# Replay — native macOS

A native Swift port of Replay, a private timeline of the apps you use. Everything stays
on the Mac: no cloud, no account, no network code, and no permissions requested.

The [Glaze version](https://github.com/nurkamol/replay-glaze) ships today and is the
reference implementation — [get it on the Glaze Store](https://www.glaze.app/app/replay-4fgahp).
This repo trails it deliberately, with a generated contract between them so it cannot trail
it *silently*.

## What Replay does, and what it will not do

It records **which application is in front, and when you were away from the keyboard.** That
is the entire input. From it Replay builds a day you can read back: sessions, the shape of
your hours, what you kept coming back to, and a history that grows into something worth
looking at months later.

What it never does:

- **No permissions.** Not Accessibility, not Automation, not Screen Recording. It reads which
  app is frontmost through the standard macOS signal every app can see, and nothing else. If
  a feature seemed to need a permission, it was the wrong feature.
- **It cannot see inside your windows.** No titles, no documents, no URLs, no keystrokes, no
  screenshots. Only an application's name and how long it was in front.
- **No network.** No account, no cloud, no telemetry, no crash reporting, no update check —
  there is no networking code in the app at all. Your record is a SQLite file in
  `~/Library/Application Support/app.replay.native/`, and it has never left your Mac.
- **It describes rather than grades.** No score, no productivity rating, no "distracting" label
  on anything. A day that was mostly a browser is described as a day mostly in a browser.

These are checked, not promised. `swift test` runs 932 contract checks against the reference
implementation, and the claims above are the ones the design is built around — see
[docs/SPEC.md](docs/SPEC.md), which is the file to read before changing anything.

## Install

There is no download yet, and that is deliberate rather than unfinished — see below.

### With Homebrew

```sh
brew tap nurkamol/tap

brew install --HEAD nurkamol/tap/replay-app    # the application
brew install --HEAD nurkamol/tap/replay        # the command-line reader
```

Then link the app once, so Spotlight and the Dock can find it:

```sh
ln -sfn "$(brew --prefix)/opt/replay-app/Replay.app" /Applications/Replay.app
```

`--HEAD` because there is no tagged release yet; it drops off once there is one.

### Or from source

```sh
git clone https://github.com/nurkamol/replay-swift.git
cd replay-swift
./scripts/make-app.sh release
open build/Replay.app
```

### If you downloaded a build

**You will see a warning the first time, and it is not about this app.**

macOS marks *everything* downloaded through a browser with a quarantine flag, and refuses to
open anything under that flag unless it carries a paid Apple Developer ID signature. Replay
does not have one yet, so the message is about a missing certificate rather than anything
found in the app.

What you will see: **"Apple could not verify Replay is free of malware"**, offering only
*Move to Trash* or *Cancel*. To open it anyway:

1. Try to open it once and dismiss the warning.
2. **System Settings ▸ Privacy & Security**, scroll down, and click **Open Anyway**.
3. Confirm. It opens normally from then on.

Or, in a terminal, one line:

```sh
xattr -dr com.apple.quarantine /Applications/Replay.app
```

**Ignore any instruction to "right-click and choose Open".** That bypass existed for years and
**Apple removed it in macOS 15**; it is still the advice in most projects' READMEs and it no
longer does anything. System Settings is the route now.

**None of this applies to the two routes above.** Homebrew and a source build compile on your
machine, so nothing is ever downloaded and nothing is ever quarantined — they open with no
warning at all. That is the reason they are listed first rather than as a fallback.

### Why there is no signed download

A disk image from a release page needs a **Developer ID signature and Apple notarisation** to
open without that warning — measured, not assumed, in [docs/FINDINGS.md](docs/FINDINGS.md),
along with the archive formats that were tested and do not avoid it. That means the Apple
Developer Program, which is **$99 a year**. There is no free path to it: a free Apple account
issues certificates that sign apps for your own machines only.

It is worth being plain that this is the *only* thing standing in the way. Everything else is
built: `scripts/make-dmg.sh` produces the image, `.github/workflows/release.yml` signs,
notarises, staples and publishes it, and both refuse to run rather than produce something
Gatekeeper will reject. The day a certificate exists, a signed download is one tag away.

Automatic updates are a separate decision and deliberately not built. The usual answer is
Sparkle, which is an external dependency — this project has none, on purpose, and that rule
would be changed openly rather than in passing. See [docs/BACKLOG.md](docs/BACKLOG.md) §6.

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

PARITY OK — 932 checks against Glaze 2.3.2
```

## What is here

```
Sources/ReplayCore/
  Model.swift            events, sessions, summaries, Rules (the thresholds)
  ActivityStore.swift    SQLite: storage, headlines, deletion, compaction
  SessionBuilder.swift   the derivation — rows → named sessions and breaks
  ActivityTracker.swift  NSWorkspace + idle time → recorded sessions
Sources/ParityKit/       the parity suite — 932 checks against the reference
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
Formula/                 Homebrew formulae — build from source, so no Developer ID
                           replay.rb the CLI · replay-app.rb the application
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

**A caveat worth reading before trusting the number.** 932 checks cover the core and the
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
