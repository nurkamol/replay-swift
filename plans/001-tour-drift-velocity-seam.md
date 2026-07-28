# 001 — Remove the velocity seam between the Canvas tour's flight and its drift

- **Status**: DONE
- **Commit**: 0e1b604
- **Severity**: MEDIUM
- **Category**: Interruptibility & physicality (AUDIT §3, §4)
- **Estimated scope**: 1 file, ~4 lines

## Problem

Replay Story flies the camera to a stop, then spends the rest of the dwell leaning
toward the next stop. The two motions are chained in time but not in velocity, so the
camera decelerates to a complete stop and then jerks into a constant creep.

The flight eases out — it ends at zero velocity:

```swift
// Sources/ReplayApp/CanvasView.swift:343 — current, inside centre(on:zoom:seconds:)
withAnimation(motion.animation(Design.Motion.camera(seconds))) {
    zoom = target
    offset = landing
    dragged = .zero
    also?()
}
```

`Design.Motion.camera` is an eased-out cubic:

```swift
// Sources/ReplayApp/DesignSystem.swift:275 — current
static let easeOutCubic = UnitCurve.bezier(
    startControlPoint: .init(x: 0.215, y: 0.61), endControlPoint: .init(x: 0.355, y: 1)
)
static func camera(_ seconds: TimeInterval) -> Animation {
    .timingCurve(easeOutCubic, duration: seconds)
}
```

The drift then starts at constant velocity, from rest:

```swift
// Sources/ReplayApp/CanvasView.swift:319 — current, inside drift(from:toward:over:)
withAnimation(.linear(duration: seconds)) {
    offset = CGSize(width: -target.x * zoom, height: -target.y * zoom)
}
```

The sequencing that puts them back to back:

```swift
// Sources/ReplayApp/CanvasView.swift:352-357 — current, inside startTour(from:)
try? await Task.sleep(for: .seconds(flight))
if Task.isCancelled { return }
if index + 1 < path.count {
    drift(from: stop, toward: path[index + 1], over: held)
}
```

Why it matters: the whole point of the drift, per its own doc comment, is that "the story
is one movement instead of a run of separate ones". A linear ramp starting from a dead stop
produces exactly the seam it was added to remove — the camera visibly arrives, pauses, and
then starts creeping. Apple's *Designing Fluid Interfaces* calls this a velocity
discontinuity and describes it as hitting a brick wall in reverse.

This is also the one place in the file that uses a bare `.linear(...)` instead of a token.

## Target

The drift accelerates gently out of the rest the flight left it in, and settles into the
next flight. `easeInOut` is the correct family here per AUDIT §2 ("Moving / morphing on
screen → ease-in-out"), and the repo already owns a strong ease-in-out-shaped curve pair.

Add one token beside the camera's own curve:

```swift
// Sources/ReplayApp/DesignSystem.swift — target, immediately after `camera(_:)`
/// The lean between two stops of a story. Eased at both ends rather than linear: the
/// flight before it ends at rest, so a constant-velocity creep starting from that rest
/// is a visible jerk — the seam this drift exists to remove. Slow in, slow out, and the
/// story reads as one movement.
static let easeInOutCubic = UnitCurve.bezier(
    startControlPoint: .init(x: 0.645, y: 0.045), endControlPoint: .init(x: 0.355, y: 1)
)
static func drift(_ seconds: TimeInterval) -> Animation {
    .timingCurve(easeInOutCubic, duration: seconds)
}
```

and use it:

```swift
// Sources/ReplayApp/CanvasView.swift:319 — target
withAnimation(Design.Motion.drift(seconds)) {
    offset = CGSize(width: -target.x * zoom, height: -target.y * zoom)
}
```

Values: `cubic-bezier(0.645, 0.045, 0.355, 1)` is the standard ease-in-out-cubic, the
symmetric partner of the `easeOutCubic` already in this file (`0.215, 0.61, 0.355, 1`).
Duration is unchanged — it stays `held`, computed as
`max(0, Design.Motion.tourDwellSeconds - flight)`.

## Contract impact

**None.** Checked before writing this plan. `spec/constants.json` carries these canvas tour
keys and no others: `tourDwellMillis`, `tourNeighbours`, `tourCameraMillis`, `tourEndZoom`,
`tourStepZoom`. The drift is this port's own invention with no counterpart upstream — its
doc comment at `DesignSystem.swift:305` says so — and `tourDriftShare` is not in the spec.
No mirrored value in `Sources/ParityKit/MotionChecks.swift` changes. The parity suite must
still report the same number of checks after this change.

## Repo conventions to follow

- **No view spells a number.** `node tools/design-audit.mjs` fails the build if a view
  contains a numeric literal in a visual position. The curve and the duration helper must
  live in `Sources/ReplayApp/DesignSystem.swift`; the view asks for `Design.Motion.drift(_:)`.
- **Motion helpers are named for what they carry, not for their shape.** Exemplar:
  `Design.Motion.camera(_:)` at `DesignSystem.swift:284` — "so a view asks for a flight and
  not for a curve." `drift(_:)` follows the same pattern deliberately.
- **Reduced motion is already handled** at the top of `drift(from:toward:over:)`
  (`CanvasView.swift:312`: `guard seconds > 0, !motion.reduced, ...`), so the new animation
  needs no `motion.animation(...)` wrapper — the function returns early. Do not add one;
  it would be dead.
- Comments explain *why*, in prose, and are expected. Match the surrounding density.

## Steps

1. In `Sources/ReplayApp/DesignSystem.swift`, immediately after the `camera(_:)` function
   (around line 284), add the `easeInOutCubic` curve and the `drift(_:)` helper exactly as
   written under **Target**, including the doc comment.
2. In `Sources/ReplayApp/CanvasView.swift`, line 319, replace
   `withAnimation(.linear(duration: seconds)) {` with
   `withAnimation(Design.Motion.drift(seconds)) {`. Leave the body unchanged.
3. Update the doc comment on `drift(from:toward:over:)` (around `CanvasView.swift:310`) to
   say the lean is eased at both ends and why, in one sentence.

## Boundaries

- Do NOT touch `Design.Motion.camera`, `easeOutCubic`, `tourCameraSeconds`,
  `tourDwellSeconds`, `tourDriftShare`, or any value mirrored in
  `Sources/ParityKit/MotionChecks.swift`.
- Do NOT change the tour's sequencing, timing, or the `Task.sleep` durations in
  `startTour(from:)`.
- Do NOT touch the screensaver's `.linear(...)`. That one is correct — constant motion
  takes a linear curve (AUDIT §2), and it is a marquee.
- Do NOT add dependencies.
- If line 319 does not read `withAnimation(.linear(duration: seconds)) {`, STOP and report:
  the file has drifted since commit 0e1b604.

## Verification

- **Mechanical**:
  - `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && swift build`
    — expect `Build complete!`
  - `node tools/design-audit.mjs` — expect "every view reads its values from Design, and the
    parity mirror still matches it."
  - `swift run replay-parity` — expect `PARITY OK — 882 checks`. **The count must not
    change.** If it does, something contract-checked was touched; revert and report.
- **Feel check**: `./scripts/make-app.sh && open build/Replay.app`, go to Canvas (⌘0 or the
  sidebar), select a node and start Replay Story. Watch the transition between two stops:
  - The camera must never come to a visible dead stop before the lean begins. Arrival and
    lean should read as one continuous slowing-and-carrying-on.
  - The lean must not end abruptly either — it should be slowest just before the next flight
    picks up.
  - Compare against the current build side by side if possible; the seam is most obvious on
    the middle stops of a long story, where flight and dwell are both full length.
- **Reduced motion**: System Settings ▸ Accessibility ▸ Display ▸ Reduce motion. The story
  must still play, the camera must still move between stops, and there must be no lean at
  all (the `guard` drops it). Nothing should regress here — this plan does not touch that path.
- **Done when**: the build is clean, the parity count is unchanged at 882, and the camera
  reads as one movement across a stop boundary rather than two.
