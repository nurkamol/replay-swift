# Replay — native macOS port

Native Swift port of Replay, a private local timeline of the apps you use. **The Glaze
version ships today and is the reference implementation** — it lives at
`~/Library/Application Support/app.glaze.macos.main/apps/replay-local-25gyn8jy/.glaze-sources`
(TypeScript, Electron-like SDK). When the two disagree about behaviour, Glaze is right.

## Read first

- `docs/SPEC.md` — the invariants. **Read before writing feature code.** The constants
  are checked automatically; these rules are the ones that get ported wrong.
- `docs/SYNC.md` — how the generated contract works and the change loop.
- `docs/PORTING-MAP.md` — Glaze API → native equivalent, scope, risks.
- `docs/SIGNING.md` — the three signing tiers and why the middle one exists. Read before
  touching `make-app.sh`'s signing block, the cask, or anything about updates: the identity
  a build carries decides whether a reader re-approves Replay on every single update.
- `docs/PARITY.md` — status ledger. Update it in the same commit as the code.
- `docs/BACKLOG.md` — **the only list of remaining work**, in the order it is worth doing.
  (`docs/ROADMAP.md` is retired and kept as history — it argued for features that are all
  built now. If the two disagree, the backlog is right.)
  Check the code before starting anything on it: the ledger has been wrong twice, and both
  times it sent work toward something already built.

## Commands

```bash
# Xcode 27 beta is installed but not selected, so point at it for anything test-related:
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

swift build                     # ReplayCore + the parity suite
swift test                      # 971 parity checks + 99 behaviour cases
swift run replay-parity         # the same suite without Xcode (CI, SSH, plain CLT)
xed .                           # Xcode, no .xcodeproj needed — pick the ReplayUI scheme
                                #   for previews; REPLAY_DB=… for a scratch record on ⌘R
./tools/xcode/install-schemes.sh  # writes the "Replay (bundle)" scheme; run once per clone
node tools/sync-spec.mjs        # regenerate spec/ from the Glaze sources
node tools/port-queue.mjs      # what changed in Glaze that this port still owes
node tools/design-audit.mjs     # fails if any view hard-codes a value instead of a token
./tools/screenshots.sh          # every surface captured to build/screenshots/, plus a contact sheet
node tools/strings-audit.mjs    # how much copy a translator can reach; --list for all of it
node tools/version-audit.mjs    # the version agrees in all four places it is written down
node tools/shortcut-audit.mjs   # fails if a bound key is undocumented, or documented and unbound
node tools/symbol-audit.mjs     # every SF Symbol exists on the deployment target's macOS
./tools/cli-audit.sh            # the CLI's exit codes, stream discipline and --json shape
swift run replay -- today       # the record from a shell; `replay help` for the rest
./scripts/make-app.sh           # assemble a runnable .app
./scripts/make-dmg.sh           # a disk image; --release signs, notarises and staples it
node tools/release-notes.mjs 0.9.7 --check   # the tag, the build and the changelog agree
```

## Rules for working here

- **Start a session with `node tools/port-queue.mjs`.** It lists the Glaze commits since
  this port last caught up, split into behaviour (the spec covers it) and UI (nothing does).
- **`spec/` is generated. Never hand-edit it.** Change behaviour in the Glaze app, run
  `node tools/sync-spec.mjs`, and the resulting `git diff spec/` is the porting work.
- **Look at the interface before claiming it works.** `./tools/screenshots.sh` drives the app
  through every surface and writes a PNG each, in about two minutes. The suites have never
  caught a layout bug — a banner over the day's headline, a dead column on a wide window, a
  caption that rendered nowhere, five buttons at five weights were all found by looking, and
  all were invisible to 951 checks. It is not a UI test and makes no assertions: it makes
  looking cheap, and a person answers "does this read badly" from an image in a second.
- **Run the parity suite before committing** (`swift test`, or `swift run replay-parity`
  without Xcode). If it fails, either this port has not caught up or `spec/` is stale. Do
  not "fix" it by editing the spec. CI runs the same suite on every push and pull request,
  in four timezones — but only against `spec/` as committed. Whether the *contract* is
  current is what `node tools/port-queue.mjs` answers, and only with the Glaze app present.
- **Commit `spec/` together with the Swift change** that matches it, so every commit says
  which upstream version it corresponds to.
- **Two run schemes, and the difference matters.** `ReplayApp` runs the bare executable
  SwiftPM builds — fastest loop, and what you want for logic. It has *no `Info.plist`*, so
  that copy has no version, no icon, no App Intents, and **no bundle identifier**, which
  means `AppDelegate`'s one-at-a-time guard cannot run. `Replay (bundle)` assembles
  `build/Replay.app` in a build post-action and launches that instead — slower, and the app
  as it actually ships. Both build **debug** on purpose: `REPLAY_DB` is inside `#if DEBUG`,
  so a release build ignores the scratch record and opens the real one, and a second Replay
  on your true history will zero the first one's live session on launch.
  · The bundle scheme is **generated, not committed** — `./tools/xcode/install-schemes.sh`.
    Xcode's `PathRunnable` takes no relative path and expands no setting that exists here:
    `SRCROOT` is undefined for a SwiftPM package, in build settings and in a post-action's
    environment alike. Both were checked rather than assumed.

- **The interface lives in `Sources/ReplayUI/`, a library.** `Sources/ReplayApp/` is five
  lines of `main.swift` plus `Intents.swift`, and that is deliberate: Xcode's canvas cannot
  preview an executable target — it wants `ENABLE_DEBUG_DYLIB`, which SwiftPM has no way to
  express — so the views had to live somewhere it can inject into. `AppDelegate` is the only
  public symbol; keep it that way. Add `#Preview` blocks (in `#if DEBUG`) as you touch views:
  the canvas is the fastest way to see one surface, and `./tools/screenshots.sh` still the
  way to see all of them. Intents stay in `ReplayApp` because `make-app.sh` passes the
  metadata processor `--module-name ReplayApp`, and moving them fails silently.
- **No view spells a number.** Every visual constant — radius, spacing, type, motion,
  colour, icon size, window metric — lives in `Sources/ReplayUI/DesignSystem.swift`, and
  `node tools/design-audit.mjs` fails the build if a view hard-codes one. The motion values
  are the reference's own and are checked by the parity suite, so the two apps move alike.
- **Deployment target is macOS 14** (Sonoma), lowered from 26 on 2026-07-29. Exactly two
  APIs in the interface begin later and both are guarded: `glassEffect` (26) in
  `DesignSystem.swift`, and `Color.mix(with:by:)` (15) in `SkyView.swift`. Measured by
  building against each floor in turn, not assumed — the earlier note here claimed the
  interface leaned on those versions broadly, and it leaned on two calls.
  · **macOS 13 is the real wall**, and it is not a gate: `@Observable` and
    `ContentUnavailableView` begin at 14, and the models use Observation throughout.
    Going lower means `ObservableObject`/`@Published` everywhere.
  · Below 26 the Surfaces setting offers Solid and Frosted only — see `SurfaceStyle.offered`.
    A stored `glass` from a newer Mac draws as frosted rather than as nothing.
  · **Nothing here has been run on macOS 14.** It compiles for it and the guards are checked
    by the suite; CI is still pinned to `macos-26` because that is the runner available, so
    the claim is "builds for 14", not "tested on 14". Worth a real Sonoma machine before the
    next release says otherwise.
- **No external dependencies.** SQLite from the system (`import SQLite3`), AppKit,
  SwiftUI. Nothing to resolve, nothing to vendor. Do not add GRDB — the SQL here has to
  stay readable against the reference implementation's SQL.
- **Timestamps are epoch milliseconds** everywhere below the UI. Not seconds, not `Date`.
- **The app must request no permissions.** No Accessibility, no Automation, no Screen
  Recording. If a feature seems to need one, it is the wrong feature — that property is
  the product.
- **Toolchain:** Xcode 27 beta at `/Applications/Xcode-beta.app` (Swift 6.4), but it is
  **not** the selected developer directory — `swift test` fails with "no such module
  'Testing'" unless `DEVELOPER_DIR` points at it. The suite lives in `ParityKit` so it
  runs both through swift-testing and as an executable; keep it that way, so the checks
  stay runnable on a machine with only Command Line Tools.

## Where things stand

The core is done and verified: storage, session derivation, and the tracker all match the
Glaze app — **971 checks**. **The UI is built**: all 20 of the reference's routes and both of
its display modes, plus a good deal it does not have — scheduled reports, a CLI, App Intents,
in-app updates, a language picker, permission rows.

**Parity with the reference is not the remaining work.** `node tools/port-queue.mjs` reports
nothing owed, and `docs/BACKLOG.md` §1 and §2 are closed. What is left is this port's own:

- **Runtime-assembled copy in the other languages.** Memories and the day's story are done;
  the autobiography, the morning briefing, Collections and Projects are not. Roughly fifty
  sentences. See `docs/TRANSLATING.md`, and **do not trust a coverage percentage** — it counts
  keys that exist, and copy that never reaches `Loc` is not one. Running the app in another
  language and *looking* is the only thing that has ever found these.
- **Previews on the remaining surfaces** — 12 of 25, added as a surface is touched.
- Signing, and the widget behind it. Not to be raised; it will be raised when it is time.

`docs/PARITY.md` is the ledger of what is already true, including a table of this port's own
work that the reference has no contract for.
