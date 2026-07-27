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
  Check the code before starting anything on it: the ledger has been wrong twice, and both
  times it sent work toward something already built.

## Commands

```bash
# Xcode 27 beta is installed but not selected, so point at it for anything test-related:
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

swift build                     # ReplayCore + the parity suite
swift test                      # 761 parity checks + 60 behaviour cases
swift run replay-parity         # the same suite without Xcode (CI, SSH, plain CLT)
node tools/sync-spec.mjs        # regenerate spec/ from the Glaze sources
node tools/port-queue.mjs      # what changed in Glaze that this port still owes
node tools/design-audit.mjs     # fails if any view hard-codes a value instead of a token
node tools/shortcut-audit.mjs   # fails if a bound key is undocumented, or documented and unbound
./scripts/make-app.sh           # assemble a runnable .app
```

## Rules for working here

- **Start a session with `node tools/port-queue.mjs`.** It lists the Glaze commits since
  this port last caught up, split into behaviour (the spec covers it) and UI (nothing does).
- **`spec/` is generated. Never hand-edit it.** Change behaviour in the Glaze app, run
  `node tools/sync-spec.mjs`, and the resulting `git diff spec/` is the porting work.
- **Run the parity suite before committing** (`swift test`, or `swift run replay-parity`
  without Xcode). If it fails, either this port has not caught up or `spec/` is stale. Do
  not "fix" it by editing the spec. CI runs the same suite on every push and pull request,
  in four timezones — but only against `spec/` as committed. Whether the *contract* is
  current is what `node tools/port-queue.mjs` answers, and only with the Glaze app present.
- **Commit `spec/` together with the Swift change** that matches it, so every commit says
  which upstream version it corresponds to.
- **No view spells a number.** Every visual constant — radius, spacing, type, motion,
  colour, icon size, window metric — lives in `Sources/ReplayApp/DesignSystem.swift`, and
  `node tools/design-audit.mjs` fails the build if a view hard-codes one. The motion values
  are the reference's own and are checked by the parity suite, so the two apps move alike.
- **Deployment target is macOS 26**, with `swift-tools-version: 6.2` because `.v26` was
  introduced there. Raised on purpose: the interface leans on APIs that begin at 15 and 26.
  `ReplayCore` needs none of them, so the parity suite still runs anywhere the toolchain
  does — but CI needs a runner at least that new, which is why it is pinned to `macos-26`.
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
Glaze app — 761 checks. **The UI is largely built**: an application menu, a menu bar item,
Today (headline, focus goal, reflection), the Timeline, a reopened past day, Search, Memories, Collections, a
session's notes/tags/bookmarks, Settings, and export — reports as Markdown, CSV, JSON or
HTML, plus full backups, and a screensaver. Counted against the reference's own router, this port now has **all 20 of its routes**. What
is left is in `docs/BACKLOG.md` — the Settings copy, the surfaces nobody has audited, and signing, which is blocked on a Developer ID rather than on code. `docs/PARITY.md` is the ledger of what is already true.
