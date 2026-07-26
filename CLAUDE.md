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

## Commands

```bash
# Xcode 27 beta is installed but not selected, so point at it for anything test-related:
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

swift build                     # ReplayCore + the parity suite
swift test                      # 298 checks against the Glaze app — run before every commit
swift run replay-parity         # the same suite without Xcode (CI, SSH, plain CLT)
node tools/sync-spec.mjs        # regenerate spec/ from the Glaze sources
node tools/port-queue.mjs      # what changed in Glaze that this port still owes
./scripts/make-app.sh           # assemble a runnable .app
```

## Rules for working here

- **Start a session with `node tools/port-queue.mjs`.** It lists the Glaze commits since
  this port last caught up, split into behaviour (the spec covers it) and UI (nothing does).
- **`spec/` is generated. Never hand-edit it.** Change behaviour in the Glaze app, run
  `node tools/sync-spec.mjs`, and the resulting `git diff spec/` is the porting work.
- **Run the parity suite before committing** (`swift test`, or `swift run replay-parity`
  without Xcode). If it fails, either this port has not caught up or `spec/` is stale. Do
  not "fix" it by editing the spec.
- **Commit `spec/` together with the Swift change** that matches it, so every commit says
  which upstream version it corresponds to.
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
Glaze app — 298 checks. **The UI is under way**: a menu bar item, Today, the Timeline, a
reopened past day, and a session's notes, tags and bookmarks are built; Settings,
reflections, and export are not. See `docs/PARITY.md` for the ledger and the next three
things worth doing.
