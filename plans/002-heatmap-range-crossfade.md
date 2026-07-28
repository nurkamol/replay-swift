# 002 — Cross-fade the heatmap's Week / Month / Year switch

- **Status**: DONE
- **Commit**: 0e1b604
- **Severity**: LOW (missed opportunity — additive, not corrective)
- **Category**: Missed opportunities (AUDIT §8)
- **Estimated scope**: 1 file, ~6 lines

## Problem

"Browse by date" in Memories offers three ranges behind a segmented control. The three
render structurally different things — 53 columns of 11pt squares, a 7×6 calendar of 34pt
cells with dates in them, a row of seven 62pt cells with durations in them — and switching
between them teleports:

```swift
// Sources/ReplayApp/MemoriesView.swift:376-380 — current
switch range {
case .year: yearGrid
case .month: monthGrid
case .week: weekRow
}
```

There is no transition and no animation on `range`. One grid vanishes and a differently
shaped one appears in the same frame, and the card's height changes with it, so the
caption and everything below jump too.

Why it matters: this is exactly AUDIT §8's "state changes that teleport (content swaps,
layout jumps) where a brief transition would prevent a jarring change." It is also a
control that invites repeated use — the whole point of three ranges is comparing them —
so the seam is seen often rather than once.

Note the frequency test (AUDIT §1) *passes* here: this is a pointer-driven control on a
browsing surface, not a keyboard action hit a hundred times a day. It has earned a
transition. The sidebar's ⌘1–⌘9 section switching, by contrast, correctly has none — do
not "fix" that.

## Target

A cross-fade only. No movement, no scale: the three grids share a purpose but not a shape,
and sliding one out while another slides in would imply a spatial relationship that does
not exist. Opacity is the honest transition for "same question, different resolution".

```swift
// Sources/ReplayApp/MemoriesView.swift — target
Group {
    switch range {
    case .year: yearGrid
    case .month: monthGrid
    case .week: weekRow
    }
}
// The three ranges answer one question at three resolutions, so they cross-fade
// rather than move: a slide would claim a spatial relationship between a year and a
// week that there is not one of. The card's height changes with the range, so the
// same animation carries the reflow of everything below it.
.transition(motion.transition(.opacity))
.animation(motion.animation(Design.Motion.inPlace), value: range)
```

Values: `Design.Motion.inPlace` is `.timingCurve(easeStandard, duration: 0.180)` —
180ms, inside AUDIT §2's 150–250ms budget for a dropdown-class change, and already the
token this app uses for "state changing in place: a card expanding, a selection moving",
which is precisely what this is. Do not introduce a new duration.

`Heatmap` does not currently read the motion environment. Add it beside the other
`@State`/`@Environment` properties at the top of the struct:

```swift
// Sources/ReplayApp/MemoriesView.swift — target, beside `@Environment(\.themeTint)`
@Environment(\.motion) private var motion
```

## Contract impact

**None.** No value in `spec/constants.json` or `Sources/ParityKit/MotionChecks.swift` is
read or changed. `Design.Motion.inPlace` is used as-is. The parity count must stay at 882.

## Repo conventions to follow

- **Reduced motion goes through the environment wrapper, never a raw animation.**
  `motion.animation(_:)` returns `nil` when motion is reduced; `motion.transition(_:)`
  degrades to `.opacity`. Exemplar: `Sources/ReplayApp/ReplayDayView.swift:40` —
  `.transition(motion.transition(.opacity.combined(with: .scale(scale: 0.98))))`.
- **No view spells a number** — `node tools/design-audit.mjs` enforces it. Use the
  `Design.Motion.inPlace` token; do not write `0.18`.
- Sixteen views in this app declare `@Environment(\.motion)` and never use it (see plan
  003). Do not imitate those. Add the property here only because this plan uses it.

## Steps

1. In `Sources/ReplayApp/MemoriesView.swift`, in the `Heatmap` struct, add
   `@Environment(\.motion) private var motion` beside the existing
   `@Environment(\.themeTint) private var tint`.
2. Wrap the `switch range { ... }` block (around line 376) in a `Group { ... }`.
3. Attach `.transition(motion.transition(.opacity))` and
   `.animation(motion.animation(Design.Motion.inPlace), value: range)` to the `Group`,
   with the explanatory comment from **Target**.

## Boundaries

- Do NOT animate the segmented `Picker` itself — it has its own system behaviour.
- Do NOT add a slide, scale, or matched-geometry effect between the three grids.
- Do NOT touch the sidebar's section switching in `RootView.swift:600`. Its lack of a
  transition is correct: ⌘1–⌘9 is a keyboard action and AUDIT §1 says keyboard-initiated,
  high-frequency actions get no animation, ever.
- Do NOT change `Design.Motion.inPlace` or any other token's value.
- If the `switch range` block is not at approximately line 376 or does not match the
  excerpt above, STOP and report: the file has drifted since 0e1b604.

## Verification

- **Mechanical**:
  - `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && swift build`
    — expect `Build complete!`
  - `node tools/design-audit.mjs` — expect the pass line.
  - `swift run replay-parity` — expect `PARITY OK — 882 checks`, unchanged.
- **Feel check**: `./scripts/make-app.sh && open build/Replay.app`, ⌘8 for Memories, scroll
  to "Browse by date":
  - Click Week → Month → Year → Week in quick succession. The switch must never restart
    from zero or double-expose two grids at readable opacity; SwiftUI transitions retarget,
    so rapid clicking should stay smooth.
  - The card's height change should be carried by the same 180ms, not snap ahead of the
    fade.
  - Confirm the caption line ("Darker is busier…" / the scroll hint) does not flicker as
    the grid swaps.
- **Reduced motion**: System Settings ▸ Accessibility ▸ Display ▸ Reduce motion, then switch
  ranges. The change should be instant — `motion.animation` returns `nil` — and must still
  be correct, with no half-faded grid left on screen.
- **Done when**: build clean, parity unchanged at 882, and switching ranges reads as one
  view resolving into another rather than two views swapping.
