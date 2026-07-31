# Replay — native macOS

A native Swift port of Replay, a private timeline of the apps you use. Everything stays
on the Mac: no cloud, no account, no permissions requested, and nothing uploaded ever.

**[nurkamol.github.io/replay-swift](https://nurkamol.github.io/replay-swift/)** — screenshots,
and the install instructions in a form you can hand to somebody.

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
- **Nothing is uploaded.** No account, no cloud, no telemetry, no crash reporting, no
  analytics. Your record is a SQLite file in
  `~/Library/Application Support/app.replay.native/`, and it has never left your Mac.
  There is exactly one network request in the app, it is **off by default**, and it is a
  `GET` to GitHub's public releases API asking whether a newer version exists —
  Settings ▸ About. It carries no identifier and no body, it is the same request your
  browser makes opening the releases page, and it downloads nothing. Leave the switch
  alone and Replay opens no connection at all. Nothing about your record is ever sent
  under any setting.
- **It describes rather than grades.** No score, no productivity rating, no "distracting" label
  on anything. A day that was mostly a browser is described as a day mostly in a browser.

These are checked, not promised. `swift test` runs 965 contract checks against the reference
implementation, and the claims above are the ones the design is built around — see
[docs/SPEC.md](docs/SPEC.md), which is the file to read before changing anything.

## Install

**Requires macOS 14 Sonoma or newer.**

### The quick way — prebuilt

```sh
brew trust --tap nurkamol/tap
brew install --cask nurkamol/tap/replay-app
```

Installs to `/Applications` in seconds, needs no developer tools, and **opens with no
warning**. Two notes on those two lines, because both are load-bearing:

- **`brew trust` is not optional.** Homebrew 6 refuses to load a third-party tap until you
  have said you trust it, and the refusal reads like a broken tap rather than a consent
  prompt. If you have hit a confusing error installing from any tap lately, this is why.
- **`--cask`, and the full path.** `replay-app` is the cask; `replay-app-source` is the
  formula that compiles. They used to share a name, Homebrew resolved it to the formula, and
  people asking for the two-second install got a demand for a 15 GB Xcode instead.

**How it opens without a warning, stated plainly.** Replay is not notarised by Apple, so a
downloaded copy would normally be refused. The tap clears the quarantine flag on install and
on every upgrade — which means macOS did not check this app for you. What checked it is
Homebrew, against the SHA-256 in the cask: a real integrity check, but one published by the
same project that publishes the app. If you would rather Apple's check applied, take the
source route below; it is compiled on your Mac and never downloaded, so there is nothing to
check and nothing to skip.

### The quiet way — built here

```sh
brew trust --tap nurkamol/tap
brew install nurkamol/tap/replay-app-source
```

Then link it once, so Spotlight and the Dock can find it:

```sh
ln -sfn "$(brew --prefix)/opt/replay-app-source/Replay.app" /Applications/Replay.app
```

Slower, and it wants a full Xcode. In exchange **there is no warning at all**: an app compiled
on your own machine was never downloaded, so it is never quarantined. Add `--HEAD` to build the
current `main` instead of v0.9.8.

### The command-line reader

```sh
brew trust --tap nurkamol/tap
brew install nurkamol/tap/replay        # `replay today`, `replay week --json`
```

A CLI is never quarantined either way, so this one has no caveats — and unlike the app it
builds with **Command Line Tools alone**, no Xcode. The app needs Xcode for SwiftUI's macro
plugins; a shell tool that reads SQLite does not.

### Or from source

```sh
git clone https://github.com/nurkamol/replay-swift.git
cd replay-swift
./scripts/make-app.sh release
open build/Replay.app
```

### If you see a warning

**This is for the zip from the releases page.** The Homebrew cask clears the flag for you and
the source build never has one, so if you took either route above you should not meet this at
all — and if you do, something is wrong worth reporting.

macOS marks *everything downloaded* with a quarantine flag — by a browser, by `curl`, or by
Homebrew installing a cask — and refuses to open anything under that flag unless it carries a
paid Apple Developer ID signature. Replay does not have one yet, so the message is about a
missing certificate rather than anything found in the app.

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

**Where the flag comes from, and who clears it.** The zip and the cask are both downloads and
both get marked. The cask clears the mark itself in a `postflight` step, which is why the
quick route is quiet — and the cask's caveats say so out loud rather than letting it look like
the app was approved. The source build (`brew install nurkamol/tap/replay-app-source`) and
`./scripts/make-app.sh` were never downloaded, so there is no mark to clear.

**Updating does not send you back here.** Every build carries the same stable signature, so
Homebrew hands your approval forward to the new version instead of asking again — see
[docs/SIGNING.md](docs/SIGNING.md) for why that stopped working under the ad-hoc signature
this used to have, where every single update meant another trip through System Settings.

### Why there is no *signed* download

A disk image from a release page needs a **Developer ID signature and Apple notarisation** to
open without that warning — measured, not assumed, in [docs/FINDINGS.md](docs/FINDINGS.md),
along with the archive formats that were tested and do not avoid it. That means the Apple
Developer Program, which is **$99 a year**. There is no free path to it: a free Apple account
issues certificates that sign apps for your own machines only.

It is worth being plain that this is the *only* thing standing in the way. Everything else is
built: `scripts/make-dmg.sh` produces the image and `.github/workflows/release.yml` signs,
notarises, staples and publishes it. Until then a release carries a **zipped app** instead —
a zip rather than a disk image on purpose, because a `.dmg` is what a finished app arrives in
and would promise something this cannot yet deliver, and because the release notes have to
carry the Gatekeeper instructions rather than let somebody meet that dialog cold. What the
workflow will not do is attach an unsigned `.dmg`.

**Updates install themselves, and what that rests on is worth reading.** Replay can check
GitHub for a newer version — opt-in, off by default, Settings ▸ About — and the banner's
button installs it: it downloads the zip, fetches the SHA-256 the release publishes beside
it, hashes the download and compares, then checks the bundle is signed, is this application,
and is the version that was offered, before replacing itself and restarting.

The trust is **HTTPS to this repository, plus that checksum** — the same model as a Homebrew
formula with a `sha256`. It proves the bytes are the ones the release carries; it does *not*
prove the release is trustworthy, because there is no Developer ID signature to establish
authorship. Anyone who can publish to this repository can publish an update. If that is not a
trust you want to extend, leave the check off and use Homebrew, which has exactly the same
property and says so more loudly.

It refuses in three cases rather than doing damage: a copy installed by Homebrew is left to
`brew upgrade`; a copy macOS is running from its read-only translocation mount has nothing to
replace; and a read-only location refuses rather than half-installing. Not Sparkle — that is
an external dependency and this project has none, on purpose.

**You meet the Gatekeeper warning once, and never again.** The first copy is downloaded by a
browser, which is what applies the quarantine flag. An update Replay downloads itself does
not carry one — measured, in [docs/FINDINGS.md](docs/FINDINGS.md) — so it installs and
reopens with no dialog at all.

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

PARITY OK — 965 checks against Glaze 2.3.2
```

## What is here

```
Sources/ReplayCore/
  Model.swift            events, sessions, summaries, Rules (the thresholds)
  ActivityStore.swift    SQLite: storage, headlines, deletion, compaction
  SessionBuilder.swift   the derivation — rows → named sessions and breaks
  ActivityTracker.swift  NSWorkspace + idle time → recorded sessions
Sources/ParityKit/       the parity suite — 965 checks against the reference
Sources/ReplayParity/    `swift run replay-parity` — the same suite without Xcode
Sources/ReplayCLI/       `replay` — the record from a shell, needing no Developer ID
Sources/ReplayUI/        the interface — every surface, and DesignSystem.swift
Sources/ReplayApp/       main.swift and the App Intents; the rest is ReplayUI
Tests/ReplayCoreTests/   `swift test` — the same suite via swift-testing
Tests/ReplayAppTests/    115 behaviour cases over the app’s own models
spec/                    GENERATED contract — never hand-edit
tools/sync-spec.mjs      regenerates spec/ from the Glaze sources
tools/port-queue.mjs     lists Glaze commits this port still owes
tools/design-audit.mjs   fails if a view spells a visual constant
tools/shortcut-audit.mjs fails if a bound key is undocumented, or documented and unbound
tools/cli-audit.sh       the CLI's exit codes, stream discipline and --json shape
Casks/replay-app.rb      the prebuilt app, installed from the release zip
Formula/                 built from source, so never quarantined
                           replay.rb the CLI · replay-app-source.rb the application
Resources/AppIcon.icns   the product's icon, carried over from the Glaze app
docs/                    read these
scripts/make-app.sh      assemble a runnable .app
scripts/make-dmg.sh      a disk image; --release signs, notarises and staples it
scripts/icon-probe.sh    the sandbox experiment behind docs/FINDINGS.md
```

**Feature-complete at 0.9.0, and past the reference at 0.9.1.** Every route the reference
has, both of its display modes — the screensaver and ambient mode — and the whole of its
Settings. Since then: PDF export, which closes the last format the reference had and this did
not; a menu bar popover and an update check, neither of which the reference has anywhere; and
a localisation layer every string now goes through. The core was finished and verified early;
the interface was the bulk of the work, as
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

## FAQ

**Is there something I can just download and run?**
Yes — a zipped app on the [releases page](https://github.com/nurkamol/replay-swift/releases/latest),
for people who do not have Xcode and are not going to install it to try something. But read
the next answer first: macOS will refuse to open it once, and you have to go through System
Settings to allow it. That is the price of no certificate, and it is on the download rather
than hidden behind it.

No `.dmg`, and that is the distinction. A disk image is what a *finished* Mac app arrives in,
and one that makes you click through a malware warning is not that. It needs a Developer ID
signature and Apple notarisation — the Apple Developer Program, 99 USD a year — and the
workflow that builds, signs, notarises and staples it is already written. The day there is a
certificate, a real download is one tag away.

**I got "Apple could not verify Replay is free of malware".**
Expected, if you took the zip. That message is about a **missing certificate, not about
anything found in the app** — every unsigned app on macOS gets it, and it offers only *Move
to Trash* or *Cancel*, which is why it reads worse than it is. Open Replay once, dismiss it,
then **System Settings ▸ Privacy & Security ▸ Open Anyway**; or run
`xattr -dr com.apple.quarantine /Applications/Replay.app`. Full version in
[If you downloaded a build](#if-you-downloaded-a-build). Right-click ▸ Open does **not** work
— Apple removed that bypass in macOS 15, and it is still the advice in most projects'
READMEs.

**Does Replay send anything anywhere?**
Nothing about you or your record, under any setting. There is exactly one network request in
the app and it is off by default: an update check against GitHub's public releases API, in
Settings ▸ About. It has no body and no identifier, downloads nothing, and reads a public
version number — the same request your browser makes opening the releases page. Everything
else is a SQLite file in your own user folder.

**Which permissions does it need?**
None. Not Accessibility, not Automation, not Screen Recording. It reads which app is
frontmost through `NSWorkspace`, a signal every app on macOS can already see, and presence
through a single "seconds since last input" integer that says *that* you typed, never what.
If a feature seemed to need a permission, it was the wrong feature.

**Can it see what I am working on?**
No. No window titles, no documents, no URLs, no keystrokes, no screenshots. An application's
name and how long it was in front is the entire input — which is why "Replay" can tell you
that you spent four hours in an editor and nothing whatsoever about what you wrote.

**How do I update it?**
`brew upgrade nurkamol/tap/replay-app` for the prebuilt copy, or
`brew upgrade nurkamol/tap/replay-app-source` if you built it (add `--fetch-HEAD` for
`--HEAD` installs), or `git pull && ./scripts/make-app.sh release` from a clone. Since 0.9.3 the in-app banner can install it for you — it downloads the
zip, checks it against the SHA-256 published beside it, and replaces itself only when you press
the button. The check that finds it is off until you turn it on, and a Homebrew copy is left to
`brew upgrade`.

**Where is my data, and how do I get it out?**
`~/Library/Application Support/app.replay.native/replay.db`, a plain SQLite file you can open
with any tool. Settings ▸ Data exports a slice as Markdown, HTML, PDF, CSV or JSON, or the
whole database as a backup — and since 0.9.4 it can write that backup for you every day or
every week into a folder you name, keeping the eight most recent. Nothing is locked in, and
deleting the folder deletes everything.

**Does it run on Intel?**
It should — there is nothing architecture-specific in it — but it has only ever been tested
on Apple silicon, so that is the honest answer rather than a yes.

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

### Working in Xcode

There is no `.xcodeproj` and there does not need to be — `xed .` opens the package, and Xcode
treats it as a workspace with a scheme per product.

```bash
xed .                    # or: open Package.swift
```

**Previews:** select the **`ReplayUI`** scheme, then ⌥⌘↩ for the canvas. The scheme matters.
With `Replay-Package` active Xcode resolves the preview back to the executable and refuses
with *"the executable target ReplayApp needs ENABLE_DEBUG_DYLIB"* — a setting SwiftPM cannot
express. That is why the interface lives in `Sources/ReplayUI/`, a library, and
`Sources/ReplayApp/` is only `main.swift` and the App Intents.

Surfaces that read the database preview against `SampleRecord` — a believable day, three weeks
of history behind it, written to a fresh temporary directory and never to your record. Add
previews as you touch a view; `TodayView.swift` is the pattern for a surface with collaborators
and `FocusGoalCard.swift` for one without.

**Running (⌘R)** gives a bare executable, not a bundle, and it says so on stderr at launch.
Three things differ, none of them bugs to chase:

- **No `Info.plist`**, so the version reads as `Replay.version` and there is no icon.
- **No one-copy-at-a-time guard** — it keys on the bundle identifier. Quit an installed
  Replay first, or both record into one SQLite file with no busy timeout between them.
- **No notifications.** They need a real `.app` to be delivered against; `./scripts/make-app.sh`
  builds one.

**`REPLAY_DB`** points a development build at a scratch record, so stepping through a delete
does not touch yours. The shared `ReplayApp` scheme already sets it to
`~/Library/Caches/app.replay.native/dev-activity.db`, so ⌘R is safe without doing anything.
The app, the CLI and the intents all honour it because they share one path function. Debug
builds only — a released binary ignores it, so nobody ends up staring at an empty Today.

**`REPLAY_SEED`** fills that scratch record with the same sample day the previews use, so ⌘R
opens onto an app with something in it. It is in the scheme, unticked; enable it under Product
▸ Scheme ▸ Edit Scheme ▸ Run ▸ Arguments. It does nothing unless `REPLAY_DB` is also set and
the record is empty, so it cannot add invented sessions to a database anyone is keeping.

Schemes live in `.swiftpm/xcode/xcshareddata/` and are committed. `.swiftpm/xcode/xcuserdata/`
is your own Xcode state and is gitignored.

Both test runners work, and CI uses the first:

```bash
swift test                                                    # 68 + 99 cases
xcodebuild -scheme Replay-Package -destination 'platform=macOS' test
```

## Licence

[MIT](LICENSE) — Copyright © 2026 Nurkamol Vakhidov.

Note the Glaze implementation is Apache 2.0 rather than MIT. Both are mine to license, so
the split is deliberate: this port is the more permissive of the two. MIT grants no
trademark rights either way — "Replay" is the product's name, not part of what is licensed,
so please don't ship a fork calling itself Replay.
