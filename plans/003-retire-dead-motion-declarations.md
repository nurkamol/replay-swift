# 003 — Retire the motion declarations and the token nothing uses

- **Status**: DONE
- **Commit**: 0e1b604
- **Severity**: LOW
- **Category**: Cohesion & tokens (AUDIT §7)
- **Estimated scope**: 17 files, one line removed from each; one token removed; one comment corrected

## Problem

Three separate pieces of dead motion vocabulary, all of which read as intent that is not
there.

### a. Sixteen views declare the motion environment and never read it

```swift
// e.g. Sources/ReplayApp/AppsView.swift:15 — current
@Environment(\.motion) private var motion
```

Every one of these files contains zero occurrences of `motion.`:

```
AppHistoryView.swift:17   AppsView.swift:15        AutobiographyView.swift:13
ChaptersView.swift:13     CollectionsView.swift:67 CommandPalette.swift:208
LegacyView.swift:16       MuseumView.swift:17      ProjectDetailView.swift:14
ProjectsView.swift:14     RelationshipView.swift:17 SearchView.swift:171
StoryView.swift:—         TimelineView.swift:—     WeekView.swift:—
WhatsNewView.swift:—
```

(Verify each with `grep -c 'motion\.' <file>` before deleting — it must return 0.)

These views **do** respect reduced motion, but through the modifiers they call, not through
this property: `.settlesIn(_:)` reads `@Environment(\.accessibilityReduceMotion)` itself at
`DesignSystem.swift:1270`, and `RowButtonStyle` reads `\.motion` at `DesignSystem.swift:1227`.
So behaviour is correct and the declarations do nothing.

Why it matters: a reader auditing accessibility sees sixteen views that appear to handle
reduced motion themselves and cannot tell, without grepping, which ones actually branch on
it. Two files in this list — `ChaptersView.swift` has the property twice, at 13 and 113 —
which is how this kind of thing spreads.

### b. A motion token with no call sites

```swift
// Sources/ReplayApp/DesignSystem.swift:199 — current
/// Something arriving on screen.
static var entering: Animation { .timingCurve(easeSoft, duration: enterSeconds) }
```

`grep -rn 'Motion.entering' Sources/ReplayApp/*.swift` returns nothing. Arrival is done by
`Design.Motion.enter` (the spring) and `.settlesIn(_:)`. A named curve nobody calls can
drift from the rest of the system without any surface changing, which is the specific
failure mode `tools/design-audit.mjs` exists to prevent.

### c. A doc comment that contradicts its own value

```swift
// Sources/ReplayApp/DesignSystem.swift:258 — current
/// The command palette. Short and linear rather than a spring: it is a thing you
/// open by reflex, and anything that settles reads as a delay.
static let palette = Animation.easeOut(duration: 0.12)
```

The value is `easeOut`, not linear. The value is *right* — AUDIT §2 puts entrances on
ease-out, and 120ms is well inside the budget — so the comment is what is wrong. This
matters more than it looks in a codebase where the comments are the design record.

## Target

### a.

Delete the sixteen unused `@Environment(\.motion) private var motion` declarations (and the
duplicate in `ChaptersView.swift`). Nothing replaces them. Reduced motion continues to be
handled by `.settlesIn(_:)` and `RowButtonStyle`.

### b.

Delete `Design.Motion.entering` and its doc comment from `DesignSystem.swift`.

### c.

```swift
// Sources/ReplayApp/DesignSystem.swift:258 — target
/// The command palette. Short and eased out rather than a spring: it is a thing you
/// open by reflex, and anything that settles reads as a delay. Twelve hundredths is
/// long enough not to be a hard cut and short enough to read as instant.
static let palette = Animation.easeOut(duration: 0.12)
```

## Contract impact

**None.** `Design.Motion.entering` is not mirrored in
`Sources/ParityKit/MotionChecks.swift` and does not appear in `spec/constants.json` —
confirm both with grep before deleting. `pressSeconds`, `hoverSeconds`, `enterSeconds`,
`staggerSeconds`, `staggerCapSeconds`, `resultStaggerSeconds`, `resultStaggerCapSeconds`
and every canvas value **are** contract-checked and must not be touched. Note that
`entering` reads `enterSeconds`, which is contract-checked and stays — only the unused
`Animation` built from it goes. The parity count must remain 882.

## Repo conventions to follow

- `tools/design-audit.mjs` checks that `DesignSystem.swift` and the `ParityKit` mirror
  still agree. Run it after touching `DesignSystem.swift`.
- Deletions of this kind are recorded in `docs/PARITY.md` under "Known divergences to keep
  an eye on" only if they change behaviour. These do not — so add nothing there. Mention
  them in the commit message instead.

## Steps

1. For each of the sixteen files, run `grep -c 'motion\.' <file>`. If it returns 0, delete
   the `@Environment(\.motion) private var motion` line. **If it returns anything other than
   0, skip that file and note it** — the audit may have missed a use.
2. In `Sources/ReplayApp/ChaptersView.swift`, check both line 13 and line 113; delete only
   the declarations whose enclosing type contains no `motion.` use.
3. Delete `Design.Motion.entering` and its doc comment from `Sources/ReplayApp/DesignSystem.swift`.
4. Replace the `palette` doc comment with the corrected text under **Target (c)**.

## Boundaries

- Do NOT remove `@Environment(\.motion)` from `CanvasView.swift`, `FocusGoalCard.swift`,
  `MemoriesView.swift`, `ReplayDayView.swift`, `RootView.swift`, `TodayView.swift`,
  `SettingsView.swift`, `SkyView.swift`, `WelcomeView.swift`, or `DesignSystem.swift` —
  all of those genuinely use it.
- Do NOT remove `@Environment(\.accessibilityReduceMotion)` anywhere, ever.
- Do NOT change any token's *value*. This plan removes one unused token and edits one
  comment; nothing else about `Design.Motion` moves.
- Do NOT "tidy" other unused properties you notice — motion only.
- If plan 002 has already been applied, `MemoriesView.swift`'s `Heatmap` will legitimately
  use `motion.`; leave it.

## Verification

- **Mechanical**:
  - `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && swift build`
    — expect `Build complete!` with no "unused variable" warnings.
  - `node tools/design-audit.mjs` — expect the pass line.
  - `swift run replay-parity` — expect `PARITY OK — 882 checks`, unchanged.
  - `swift test` — expect 42 + 19 tests passing.
  - `grep -rn 'Motion.entering' Sources/` — expect no output.
- **Feel check**: this plan should change nothing visible. Build the app and confirm:
  - Every surface still staggers its content in on arrival (⌘1 through ⌘9 in turn).
  - Pressing any card still gives — the row still darkens and dips.
  - With Reduce Motion on, arrivals are instant and presses still darken without dipping.
  - Any visible change at all means a `motion.` use was deleted along with a declaration —
    revert and re-check step 1.
- **Done when**: build clean with no new warnings, parity unchanged at 882, no visible
  difference in the running app.
