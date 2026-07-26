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
swift build                     # ReplayCore + the parity checker
swift run replay-parity         # 188 checks against the Glaze app — run before every commit
node tools/sync-spec.mjs        # regenerate spec/ from the Glaze sources
./scripts/make-app.sh           # assemble a runnable .app (no Xcode needed)
```

## Rules for working here

- **`spec/` is generated. Never hand-edit it.** Change behaviour in the Glaze app, run
  `node tools/sync-spec.mjs`, and the resulting `git diff spec/` is the porting work.
- **Run `swift run replay-parity` before committing.** If it fails, either this port has
  not caught up or `spec/` is stale. Do not "fix" it by editing the spec.
- **Commit `spec/` together with the Swift change** that matches it, so every commit says
  which upstream version it corresponds to.
- **No external dependencies.** SQLite from the system (`import SQLite3`), AppKit,
  SwiftUI. Nothing to resolve, nothing to vendor. Do not add GRDB — the SQL here has to
  stay readable against the reference implementation's SQL.
- **Timestamps are epoch milliseconds** everywhere below the UI. Not seconds, not `Date`.
- **The app must request no permissions.** No Accessibility, no Automation, no Screen
  Recording. If a feature seems to need one, it is the wrong feature — that property is
  the product.
- **Toolchain:** Swift 6.2.3 via Command Line Tools, **no full Xcode**. So no `XCTest`,
  no `swift-testing`, no `.xcodeproj`, no notarisation. That is why the parity check is
  an executable target rather than a test target. Do not add a `.testTarget` until Xcode
  is installed — it will not compile.

## Where things stand

The core is done and verified: storage, session derivation, and the tracker all match the
Glaze app. **The UI has not been started.** `Sources/ReplayApp/main.swift` is a
placeholder. See `docs/PARITY.md` for the ledger and the next three things worth doing.
