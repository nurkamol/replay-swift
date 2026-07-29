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
node tools/sync-spec.mjs        # regenerate spec/ from the Glaze sources
node tools/port-queue.mjs      # what changed in Glaze that this port still owes
node tools/design-audit.mjs     # fails if any view hard-codes a value instead of a token
./tools/screenshots.sh          # every surface captured to build/screenshots/, plus a contact sheet
node tools/strings-audit.mjs    # how much copy a translator can reach; --list for all of it
node tools/version-audit.mjs    # the version agrees in all four places it is written down
node tools/shortcut-audit.mjs   # fails if a bound key is undocumented, or documented and unbound
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
Glaze app — 965 checks. **The UI is largely built**: an application menu, a menu bar item,
Today (headline, focus goal, reflection), the Timeline, a reopened past day, Search, Memories, Collections, a
session's notes/tags/bookmarks, Settings, and export — reports as Markdown, CSV, JSON or
HTML, plus full backups, and a screensaver. Counted against the reference's own router, this port has **all 20 of its routes**, and since
2026-07-28 both of its display modes — the screensaver and ambient mode. (A route count was
never a completeness measure: ambient mode is a *mode*, and the count could not see it.) What
is left is in `docs/BACKLOG.md` — the Settings copy, the surfaces nobody has audited, and signing, which is blocked on a Developer ID rather than on code. `docs/PARITY.md` is the ledger of what is already true.
