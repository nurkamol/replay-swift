import ReplayCore
import SwiftUI

/// Every visual constant the app has, in one place.
///
/// The rule this exists to enforce: **no view spells a number.** A radius, a gap, a
/// duration, a font size — all of them come from here, so changing one changes the whole
/// app and no surface can quietly drift from the others.
///
/// Two things this is *not*. It is not a theme engine: there is one look, and the tokens
/// name it rather than parameterise it. And it is not invented — the motion values come
/// from the reference implementation's own stylesheet via `spec/constants.json`, so the two
/// apps move alike, and the parity suite fails if they stop.
///
/// Where a token is chosen rather than inherited, it is chosen once here and the reason is
/// written next to it. The point of a scale is that the next person picks from it instead
/// of measuring.
enum Design {
    /// The thresholds the setting offers, one per band of `confidenceThresholdLabel`. Values
    /// rather than a slider: four named choices are easier to mean than a continuum.
    static let memoryThresholds: [Double] = [0.2, 0.4, 0.55, 0.8]

    /// How long the window may sit untouched before a display drifts in — the screensaver
    /// or ambient mode, whichever `IdleDisplay` names.
    static let idleStartChoices = [2, 5, 10, 20]
    /// What the welcome screen sets when its two numeric offers are accepted. Round rather
    /// than clever: someone agreeing to a goal on a first run has no basis for a precise one.
    static let welcomeGoalMinutes = 180
    static let welcomeIdleMinutes = 5
    /// The hours a daily recap can be delivered at. Evening-weighted, because a recap of a
    /// day is worth reading once the day has happened.
    static let notificationHours = [12, 15, 17, 18, 19, 20, 21, 22]
    /// Every hour, for the spans that can legitimately begin at any of them — "only between
    /// these hours" is answered with 2am as readily as with 9am, and a shortlist would be
    /// the app deciding when somebody's day is.
    static let hoursOfTheDay = Array(0..<24)


    // ── spacing ───────────────────────────────────────────────────────────────

    /// A 4pt base, which is what macOS lays out on. Sizes are named for their role rather
    /// than their measurement, so a change of scale does not turn every call site into a
    /// lie about its own name.
    enum Space {
        /// Between a glyph and its label.
        static let hairline: CGFloat = 2
        /// Inside a pill or a tight horizontal run.
        static let tight: CGFloat = 4
        /// Between closely related controls.
        static let snug: CGFloat = 6
        /// The default gap between elements in a row.
        static let inline: CGFloat = 8
        /// Between rows of a list.
        static let row: CGFloat = 10
        /// Inside a card.
        static let card: CGFloat = 12
        /// Between a card's edge and its contents when it holds a block.
        static let cardRoomy: CGFloat = 14
        /// Between distinct groups on a surface.
        static let section: CGFloat = 16
        /// Between the major blocks of a page.
        static let block: CGFloat = 20
        /// The page gutter.
        static let page: CGFloat = 24

        /// Vertical air around an empty state, which needs room to read as deliberate
        /// rather than as a rendering failure.
        static let emptyState: CGFloat = 30
        /// The same, on a surface with nothing else on it at all.
        static let emptyStateRoomy: CGFloat = 40
        /// Between the stats on a headline card, which need more separation than a row.
        static let statGap: CGFloat = 22
        /// The screensaver drifts through a tall, airy column.
        static let screensaverGap: CGFloat = 40
        static let screensaverPadding: CGFloat = 48
        /// A stack of app icons, overlapped so the group reads as one thing.
        static let iconOverlap: CGFloat = -8
    }

    /// A pill: a tag, a badge, a streak. Its own scale because the numbers are set by the
    /// glyph inside rather than by the layout around it.
    enum Pill {
        static let horizontal: CGFloat = 8
        static let vertical: CGFloat = 4
        /// A pill that ends in a close button, which needs less room on that side.
        static let trailingTight: CGFloat = 5
        static let leadingRoomy: CGFloat = 9
        /// A capsule holding only a count.
        static let countHorizontal: CGFloat = 5
        static let countVertical: CGFloat = 3
        /// A search field or a well.
        static let fieldHorizontal: CGFloat = 10
        static let fieldVertical: CGFloat = 7
    }

    // ── corner radii ──────────────────────────────────────────────────────────

    enum Radius {
        /// The Dock badge Replay draws for itself: how big the capsule is against the tile,
        /// where it sits, and the type inside it. Proportions rather than points, because a
        /// Dock tile is drawn at whatever size the Dock happens to be.
        static let dockBadgeHeight: CGFloat = 0.30
        static let dockBadgeInset: CGFloat = 0.04
        static let dockBadgeTextRatio: CGFloat = 0.62
        static let dockBadgePaddingRatio: CGFloat = 0.34

        /// A tag, a badge, an icon tile.
        /// A bar in a rhythm strip — enough to take the sharp edge off, no more.
        static let hair: CGFloat = 1.5
        static let small: CGFloat = 6
        /// A control, a well, a compact row.
        static let control: CGFloat = 8
        /// The default for a card.
        static let card: CGFloat = 10
        /// A surface that holds cards.
        static let surface: CGFloat = 14
        /// Fully rounded. Used through `Capsule()`; named so the intent is greppable.
        static let pill: CGFloat = .infinity

        /// An app icon's corner, as a fraction of its side — macOS icon geometry, so a
        /// placeholder tile matches the real icons beside it at any size.
        static let iconSquircleRatio: CGFloat = 0.22
    }

    // ── typography ────────────────────────────────────────────────────────────

    /// Named roles, expressed as **semantic text styles** rather than point sizes.
    ///
    /// This is what makes Dynamic Type work. A `Font.system(size: 15)` is 15 points at every
    /// accessibility setting; `.title3` is 15 points at the default one and grows when
    /// someone has asked the system for larger text. The role names are unchanged — a view
    /// still asks for "a session's name" — but what they resolve to now depends on the
    /// reader rather than on me.
    ///
    /// The one figure that stays a fixed size is the hero, and it is scaled explicitly by
    /// the view that draws it (see `HeadlineCard`): at 46 points it is a display figure, and
    /// no semantic style is anywhere near it.
    enum Text {
        /// The number Today exists to show. Paired with `@ScaledMetric` at the call site.
        static let heroSize: CGFloat = 46
        static func hero(_ size: CGFloat) -> Font {
            .system(size: size, weight: .bold, design: .rounded)
        }
        /// A page title.
        static let title = Font.largeTitle.weight(.bold)
        /// A card's headline figure.
        static let figure = Font.callout.weight(.medium)
        /// A session's name.
        static let itemTitle = Font.body.weight(.medium)
        /// Ordinary body copy.
        static let body = Font.body
        /// Supporting copy under a title.
        static let subtitle = Font.subheadline
        /// A row's secondary line.
        static let detail = Font.caption
        /// The same size carrying a figure rather than a note.
        static let detailStrong = Font.caption.weight(.semibold)
        /// The smallest readable label; used for counts beside an icon.
        static let micro = Font.caption2
        /// An uppercase section label. Pair with ``Design/Text/labelKerning``.
        /// A heading over a run of cards — "2 sessions" above the day's list.
        ///
        /// Distinct from `sectionLabel` because they were not: a page heading and a label
        /// printed *inside* a card came out the same size, the same weight and the same grey,
        /// so "2 SESSIONS" and "FOCUS GOAL" read as the same kind of thing when one names a
        /// section of the page and the other names a field within one card.
        static let pageSection = Font.subheadline.weight(.semibold)
        static let sectionLabel = Font.caption.weight(.semibold)
        /// The uppercase micro-label inside a card.
        static let cardLabel = Font.caption2.weight(.semibold)

        /// The PDF report's own scale.
        ///
        /// Fixed points rather than the app's semantic styles, and that is the difference
        /// between a screen and a page: `Font.body` follows the reader's Dynamic Type
        /// setting, which is right in a window and wrong in a document somebody is going to
        /// print or email — the same file would come out at a different size on every Mac.
        static let pdfTitle = Font.system(size: 22, weight: .semibold)
        static let pdfSummary = Font.system(size: 11)
        static let pdfRow = Font.system(size: 10)
        static let pdfRowDetail = Font.system(size: 9)
        static let pdfFootnote = Font.system(size: 8)
        /// Prose meant to be read rather than scanned — a day's story.
        static let prose = Font.title3
        /// A glyph small enough to sit inside a ring or a pill.
        static let ringFigure = Font.caption.weight(.medium)
        static let ringGlyph = Font.caption.weight(.bold)
        static let pillGlyph = Font.caption2.weight(.bold)
        static let closeGlyph = Font.caption2.weight(.bold)
        /// The screensaver, which is read from across a room rather than at a desk.
        static let screensaverHeading = Font.title.weight(.semibold)
        static let screensaverTitle = Font.title3.weight(.medium)
        /// The one moment on screen while a day plays back.
        static let playbackTitle = Font.largeTitle.weight(.semibold)
        static let screensaverKerning: CGFloat = 1.8

        /// Uppercase labels need loosening or they set too tight to read.
        static let labelKerning: CGFloat = 0.6
        static let tightKerning: CGFloat = 0.5
        /// Line spacing for prose. Body copy in a card needs more air than a list row.
        static let proseLineSpacing: CGFloat = 3
    }

    // ── motion ────────────────────────────────────────────────────────────────

    /// Durations and curves from the reference's stylesheet, checked by the parity suite.
    ///
    /// Two curves cover everything, both taken from the way macOS moves: `soft` decelerates
    /// hard and settles — right for things entering the screen; `standard` is the
    /// sheet/window curve, right for state that changes in place.
    enum Motion {
        static let pressSeconds: Double = 0.090
        static let hoverSeconds: Double = 0.180
        static let enterSeconds: Double = 0.460

        static let easeSoft = UnitCurve.bezier(
            startControlPoint: .init(x: 0.16, y: 1), endControlPoint: .init(x: 0.3, y: 1)
        )
        static let easeStandard = UnitCurve.bezier(
            startControlPoint: .init(x: 0.32, y: 0.72), endControlPoint: .init(x: 0, y: 1)
        )

        /// State changing in place: a card expanding, a selection moving.
        static var inPlace: Animation { .timingCurve(easeStandard, duration: hoverSeconds) }
        /// A press, which should feel like contact rather than animation.
        static var press: Animation { .timingCurve(easeStandard, duration: pressSeconds) }
        /// How far a pressed row gives. The reference's own `active:scale-[0.99]` — small
        /// enough that nobody would call it a movement, which is the point: it is contact,
        /// not choreography.
        static let pressScale: CGFloat = 0.99

        /// A list settles one row every `stagger`, capped so a long list finishes rather
        /// than trickling in for seconds.
        static let staggerSeconds: Double = 0.028
        static let staggerCapSeconds: Double = 0.560

        static func enterDelay(_ index: Int, base: Double = 0) -> Double {
            min(base + Double(index) * staggerSeconds, staggerCapSeconds)
        }

        /// A search result's own stagger, which is not the one above.
        ///
        /// The reference keeps two, and the difference is the point: a list of a day's
        /// sessions is arriving somewhere you have just navigated to, and can afford to
        /// settle; a search result is arriving under the fingers of somebody still typing,
        /// and cannot. Upstream calls it "snapping in under the fingers" — ten milliseconds
        /// a row against twenty-eight, capped at 220 against 560.
        ///
        /// This port had been using the general one for both, so the twentieth result landed
        /// at 560ms where the reference puts it at 200. Found by auditing Search; both
        /// numbers are the reference's and both are checked.
        static let resultStaggerSeconds: Double = 0.010
        static let resultStaggerCapSeconds: Double = 0.220

        static func resultDelay(_ index: Int) -> Double {
            min(Double(index) * resultStaggerSeconds, resultStaggerCapSeconds)
        }

        /// A spring for things that move rather than merely change.
        ///
        /// No bounce. Replay's motion is settling, not springing — a card arriving should
        /// look like it came to rest, and overshoot on a list of someone's day reads as
        /// playfulness the content does not have.
        static let settle = Animation.spring(duration: 0.42, bounce: 0)

        /// A section arriving. Slightly longer than a settle and with the faintest bounce,
        /// because it is coming from somewhere rather than responding to a press.
        static let enter = Animation.spring(duration: 0.46, bounce: 0.05)
        /// How far it rises. Small enough to read as arrival rather than as a slide.
        static let enterRise: CGFloat = 8
        /// What a row does as it leaves the top or bottom of a scroll. Barely anything, on
        /// purpose — enough that the edge of a list reads as an edge rather than a cut.
        static let scrollFade: Double = 0.6
        static let scrollShrink: CGFloat = 0.985

        /// How long two clicks may be apart and still be one double-click. The system's own
        /// interval would be better, but it is not reachable from inside a `Canvas` gesture,
        /// and this is the same default.
        static let doubleClickSeconds: TimeInterval = 0.4

        /// The field assembling itself when Canvas opens, and how the nodes are staggered
        /// through it. Slower than a settle, because a landscape is arriving rather than a
        /// control responding.
        /// The command palette. Short and eased out rather than a spring: it is a thing you
        /// open by reflex, and anything that settles reads as a delay. Twelve hundredths is
        /// long enough not to be a hard cut and short enough to read as instant.
        static let palette = Animation.easeOut(duration: 0.12)

        static let canvasEntranceSeconds: TimeInterval = 0.9
        static let canvasEntranceStagger: CGFloat = 0.012
        static let canvasEntranceStaggerCap: CGFloat = 0.55

        /// The canvas camera. Every value here is the reference's, and checked — see
        /// `CanvasTokens` and docs/PARITY.md.
        ///
        /// Eased rather than sprung, which is the one place the canvas parts company with
        /// the rest of this app. Elsewhere a spring is right: a card is responding to you
        /// and should look like it came to rest. A camera is not responding to you — it is
        /// travelling somewhere it already knows about — and a spring's slow tail reads as
        /// the field drifting after it arrived. The reference eases out a cubic, so this
        /// does too.
        static let easeOutCubic = UnitCurve.bezier(
            startControlPoint: .init(x: 0.215, y: 0.61), endControlPoint: .init(x: 0.355, y: 1)
        )
        /// The same cubic, eased at both ends — for movement nobody asked for in the instant
        /// it happens. A story's hops are the only thing in the app that travels unprompted,
        /// and they are the only thing that uses this.
        static let easeInOutCubic = UnitCurve.bezier(
            startControlPoint: .init(x: 0.645, y: 0.045), endControlPoint: .init(x: 0.355, y: 1)
        )
        /// The camera's own flight time, and the two journeys that ask for their own.
        static let cameraSeconds: TimeInterval = 0.560
        static let cameraCentreSeconds: TimeInterval = 0.620
        static let cameraZoomSeconds: TimeInterval = 0.340
        /// A camera move over `seconds`. Named for what it carries rather than for its shape,
        /// so a view asks for a flight and not for a curve.
        static func camera(_ seconds: TimeInterval) -> Animation {
            .timingCurve(easeOutCubic, duration: seconds)
        }

        /// A story's hop between two stops, which is **not** the same movement as a focus.
        ///
        /// `camera` eases *out* only: it is maximally fast at the first frame, which is right
        /// when somebody has just double-clicked something — the camera answering instantly is
        /// the response to the click. A story hop has no click behind it. It begins from a
        /// camera at rest, and starting at full speed from rest is a jerk; ending at zero and
        /// then jerking again at the next stop is what makes a tour read as a series of
        /// lurches rather than a journey.
        ///
        /// So this eases at both ends. Same duration — the contract pins that — and a shape
        /// that leaves and arrives at rest, which is the shape of something being *carried*.
        static func tourFlight(_ seconds: TimeInterval) -> Animation {
            .timingCurve(easeInOutCubic, duration: seconds)
        }

        /// Replay Story: how long the camera rests on each stop, and how long it takes to
        /// get between them. The dwell is longer than the flight on purpose — the pause is
        /// where you read the thing, and the travel is only how you got there. Both are the
        /// reference's own numbers and are contract-checked.
        static let tourDwellSeconds: TimeInterval = 1.150
        static let tourCameraSeconds: TimeInterval = 0.760

        /// What the field does while the story plays, which is this port's own and has no
        /// counterpart upstream — the reference's tour is the camera and the lit node, and
        /// nothing else. Kept quiet enough to stay that way in spirit: one breath per stop
        /// and a line drawing itself, rather than a thing demanding to be watched.
        ///
        /// The breath is a ring easing outward from the node and fading as it goes. It
        /// takes less than the dwell on purpose, so it finishes and leaves the stop sitting
        /// still — a ring pulsing the whole time reads as an alert.
        static let tourBreathSeconds: TimeInterval = 0.780

        /// **The camera used to lean toward the next stop while resting on this one**, over
        /// the 390ms the reference's dwell leaves after its flight. It was this port's own,
        /// and it was wrong: a hop that ends at rest, then a slow creep that also ends at
        /// rest, then a hop that starts at full speed reads as two separate stops and a
        /// lurch — which is exactly what it looked like. The dwell is still now, and the
        /// hops ease at both ends. See `Design.Motion.tourFlight`.

        /// The field's own breathing, when nothing else is happening.
        ///
        /// A sway rather than a rotation: the whole picture leans a fraction of a degree one
        /// way and then the other, and drifts around a small ellipse while it does. A true
        /// rotation would keep going, and a map of someone's history that has quietly turned
        /// ninety degrees while they read it is a map they have to find their way around
        /// again. Bounded motion is alive; unbounded motion is a problem.
        ///
        /// The two periods are deliberately not multiples of each other, so the sway and the
        /// drift never line up into a pattern anyone could learn.
        /// How often the field is redrawn when the sway is all that is moving. A third of a
        /// display's rate, because at this speed nothing is fast enough to show the seam,
        /// and a canvas this size redrawn sixty times a second for a movement nobody would
        /// name is not a trade worth making.

        /// A selection arriving. The halo eases outward into place rather than appearing,
        /// which is the difference between the field answering you and the field blinking.
        static let selectionArriveSeconds: TimeInterval = 0.28
        /// How far past the node the breath travels, as a share of the node's own radius.
        static let tourBreathReach: CGFloat = 0.85
        static let tourBreathWidth: CGFloat = 2


        /// How long one pass of the screensaver takes, and how long it takes when someone
        /// has asked the system to reduce motion — slower rather than stopped, because a
        /// screensaver that does not move is a poster.
        /// A moment's grace before the screensaver will take a dismissal, so the click or
        /// keystroke that started it does not end it in the same breath.
        static let screensaverArmSeconds: TimeInterval = 0.5

        /// How often the playhead advances. Sixty a second is more than the eye needs for a
        /// bar and a cross-fade, and it is a timer running for half a minute.
        static let playbackTick: TimeInterval = 1.0 / 30

        /// How long the sky takes to move between two hours. Long, because the point is that
        /// you notice it has changed rather than watching it change.
        static let skySeconds: Double = 1.4

        static let screensaverDriftSeconds: Double = 90
        static let screensaverSlowSeconds: Double = 240
        /// Ambient mode's breath — the icon of whatever is in front swelling and settling.
        /// The only thing on that screen that moves, which is why it is allowed to: nothing
        /// else there changes for minutes at a time, and a still image of a live number
        /// reads as a screenshot. Stopped outright when motion is reduced rather than
        /// slowed, unlike the screensaver's drift, because here the movement is decoration
        /// and there it is the content. All three values are the reference's, and checked.
        static let ambientBreatheSeconds: Double = 6
        /// How often ambient mode re-reads the day. A minute, because a minute is the
        /// resolution of everything on that screen — the clock shows minutes and the total
        /// is formatted in them — so anything faster redraws to show the same characters.
        static let ambientTick: TimeInterval = 60
        static let ambientBreatheScale: CGFloat = 1.04
        static let ambientBreatheFloor: Double = 0.96
    }

    /// A light travelling around a border, for work with no known length.
    ///
    /// **Deliberately one use.** A moving border is attention-seeking by construction, and
    /// SPEC §8 is explicit that nothing in this app asks to be watched — so it is not on the
    /// goal card when a goal is met, not on a session, not in ambient mode. It is on the
    /// update banner while an update installs, where the app is doing something you should
    /// not interrupt and genuinely cannot say for how long. When it can say, a bar says it.
    enum Beam {
        /// One trip round. Slow enough to read as a light moving, fast enough to say "still
        /// working" without a second's doubt.
        static let seconds: Double = 2.4
        /// How much of the border the bright part covers. A short arc is a chase light; this
        /// is nearly a third, which reads as a sweep.
        static let arc: Double = 0.3
        static let width: CGFloat = 1.5
        /// The dimmest the trailing edge goes, so the border never fully disappears — an
        /// outline that vanishes reads as a flicker rather than as a sweep.
        static let floor: Double = 0.18
    }

    /// Motion, with Reduce Motion respected.
    ///
    /// Not a courtesy. When someone has asked the system to stop moving things, an animation
    /// is not a nicety they are missing out on — it is the thing they asked not to happen.
    /// So this returns `nil`, and the change lands immediately rather than in a shorter
    /// animation that still moves.
    struct MotionPreference {
        var reduced: Bool

        func animation(_ animation: Animation) -> Animation? { reduced ? nil : animation }

        /// A transition that becomes a plain opacity change when motion is reduced —
        /// appearing and disappearing still need to be legible.
        func transition(_ transition: AnyTransition) -> AnyTransition {
            reduced ? .opacity : transition
        }
    }

    // ── colour ────────────────────────────────────────────────────────────────

    /// Deliberately thin, and almost entirely system materials.
    ///
    /// Replay describes a day rather than grading it (SPEC §8), so there is no palette of
    /// meaning here — no red for "bad", no green for "good". The one accent that carries a
    /// judgement is ``Design/Colour/met``, on the single evaluative surface the app has.
    enum Colour {
        /// Surfaces, in increasing prominence. Fractions of `.quaternary` so they follow
        /// the system's own contrast and adapt to light, dark and increased-contrast.
        static let surfaceQuiet = AnyShapeStyle(.quaternary.opacity(0.18))
        static let surface = AnyShapeStyle(.quaternary.opacity(0.20))
        static let surfaceRaised = AnyShapeStyle(.quaternary.opacity(0.25))
        static let surfaceInset = AnyShapeStyle(.quaternary.opacity(0.30))
        static let fill = AnyShapeStyle(.quaternary.opacity(0.40))
        static let fillStrong = AnyShapeStyle(.quaternary.opacity(0.50))

        /// A row under the pointer, and a row being pressed. Behind the row's own surface
        /// rather than over it, so what changes is the card's ground and never the legibility
        /// of what is written on it.
        ///
        /// Higher than they look like they should be, and measured rather than chosen: a
        /// card already carries a translucent fill of its own, which absorbs most of what is
        /// put behind it. At 0.14 the hover moved the picture by 0.012 mean brightness —
        /// present in a difference, invisible to a person.
        static let rowHover = AnyShapeStyle(.quaternary.opacity(0.26))
        static let rowPressed = AnyShapeStyle(.quaternary.opacity(0.40))

        static let border = AnyShapeStyle(.quaternary.opacity(0.50))
        static let borderQuiet = AnyShapeStyle(.quaternary.opacity(0.40))
        static let divider = AnyShapeStyle(.quaternary.opacity(0.60))

        /// A bookmarked session's warmed border, and its mark.
        static let marked = Color.yellow
        /// How far a bookmarked border is warmed, and a streak's background tinted.
        static let markedOpacity: Double = 0.45
        static let streakOpacity: Double = 0.12
        /// The matched run inside a search result. Light enough to leave the text primary —
        /// a highlight that has to be read *through* has stopped pointing at anything.
        static let matchOpacity: Double = 0.20

        /// A rhythm bar's weight. The busiest hour is solid and the quietest still shows,
        /// so the strip reads as a shape rather than as a row of on/off cells.
        static let arcFloorOpacity: Double = 0.45
        static let arcRangeOpacity: Double = 0.55
        static let arcQuietOpacity: Double = 0.60
        /// A day with nothing recorded, dimmed as a whole — rest, not absence.
        static let arcRestOpacity: Double = 0.50

        /// The canvas. Edges are faint so the nodes read first, and a stronger tie is a
        /// slightly stronger line rather than a different colour.
        static let canvasEdgeFloor: Double = 0.10
        static let canvasEdgeRange: Double = 0.25
        static let canvasEdgeBase: Double = 0.35
        /// How far back the field falls when something is focused. Pulled back rather than
        /// hidden — a focus that empties the page loses the thing focus is *for*, which is
        /// seeing where one memory sits among the rest.
        ///
        /// The reference's 0.1, not the 0.14 this port had drifted to. Found by auditing the
        /// Canvas after generating its *camera* into the contract and stopping there — the
        /// field's own drawing rules were left out, and this one had already moved.
        static let canvasUnfocused: Double = 0.1
        /// Zoom out past ``canvasAppsFadedBelowZoom`` and the applications fall back to
        /// ``canvasAppFaded``, leaving the things built on them — collections, projects,
        /// chapters — holding the picture. It is what makes the far view legible rather than
        /// a hundred icons at equal weight: pulling back should show you the shape of a
        /// history, not more of its detail.
        static let canvasAppFaded: Double = 0.32
        static let canvasProjectOpacity: Double = 0.65
        static let canvasChapterOpacity: Double = 0.70
        static let canvasMomentOpacity: Double = 0.80
        static let canvasAppOpacity: Double = 0.55
        /// How far the bubble's own colour is pulled back when an icon sits on it. Enough
        /// to tint the padding, not enough to become a halo.
        static let canvasBubbleBehindIcon: Double = 0.28
        /// The same bubble with the pointer on it. The reference lifts an active node's fill
        /// from 0.09 to 0.16 — its own numbers describe a differently-composed bubble, so
        /// what ports is the ratio rather than the value.
        static let canvasBubbleActive: Double = 0.50
        /// The line the camera is travelling along during a Replay Story, and the breath the
        /// stop it lands on lets out. Brighter than an ordinary edge because for a second
        /// and a half it is the only thing being said.
        static let canvasTourPath: Double = 0.85
        static let canvasTourBreath: Double = 0.55
        /// The hairline that keeps a Dock badge legible against a dark icon.
        static let dockBadgeRim: Double = 0.55
        /// A ring around an icon. An application wears a quiet one — its own icon already
        /// says what it is — and everything built on top of one wears a solid ring, so a
        /// project is never mistaken for the app whose icon it borrows.
        static let canvasRingQuiet: Double = 0.35

        /// The palette floats, so it casts something. Weighted rather than dark: a hard
        /// shadow would make it a dialog, and it is not one.
        static let paletteShadow = Color.black.opacity(0.35)
        static let scrim = Color.black.opacity(0.18)
        /// The row Return would activate. The accent rather than a grey fill: on a material
        /// panel a quaternary wash is almost invisible, and the whole point of the row is
        /// that you can see which one it is without looking for it.
        /// How far the tint is pulled back for the row Return would activate.
        static let paletteHighlightOpacity: Double = 0.30
        /// How much of the sky a card carries. Enough to notice across a day, not enough to
        /// compete with what is written on it.
        static let skyOnCard: Double = 0.55

        /// The heatmap. How much accent a square carries is `ReplayCore.Heatmap.mix`, which
        /// is the reference's own and contract-checked; these are the two things around it.
        /// A day from a neighbouring month is context rather than content, and the weekday
        /// above a figure is a label rather than the figure.
        static let outOfMonth: Double = 0.40
        static let heatCaption: Double = 0.80

        /// The screensaver. Everything is white at a chosen weight rather than a palette:
        /// the room it plays in is dark, and colour would be the thing asking for attention.
        static let screensaverBackground = Color(red: 0.027, green: 0.027, blue: 0.035)
        static let screensaverPrimary: Double = 0.80
        static let screensaverSecondary: Double = 0.70
        static let screensaverTertiary: Double = 0.35
        static let screensaverQuiet: Double = 0.30
        /// Ambient mode. Everything is white at a weight, like the screensaver, because the
        /// room it plays in is dark and colour would be the thing asking for attention.
        static let ambientHeadline: Double = 0.45
        static let ambientLabel: Double = 0.40
        static let ambientHint: Double = 0.25
        static let ambientEyebrow: Double = 0.35
        static let ambientIconRing: Double = 0.10
        static let screensaverIconOpacity: Double = 0.70
        static let screensaverFavouriteOpacity: Double = 0.80
        static let screensaverExitOpacity: Double = 0.40
        static let screensaverHintOpacity: Double = 0.20
        static let markedBorder = AnyShapeStyle(Color.yellow.opacity(0.45))
        /// A goal that was reached. The app's only approving colour.
        static let met = Color.green
        /// A streak worth celebrating.
        static let streak = Color.orange
        static let streakBackground = AnyShapeStyle(Color.orange.opacity(0.12))
        /// The privacy promise, which is the one place a claim is made in colour.
        static let assurance = Color.green
    }

    // ── the sky ───────────────────────────────────────────────────────────────

    /// What the hour looks like.
    ///
    /// Anchored to the app's *own* day parts rather than to astronomy, and that is the whole
    /// point. Replay decides on the clock alone that before 5 is late night, 5 to 12 is
    /// morning, 12 to 17 afternoon, 17 to 22 evening (`dayPart(of:)`) — so a screen that
    /// says "EVENING" over a sky that has already gone dark is the app disagreeing with
    /// itself. Real sunset would need to know where the Mac is, and this app asks for
    /// nothing; matching the label it prints is both honest and the thing that reads right.
    ///
    /// Sunrise and sunset get their own anchors close together, because that is where the
    /// sky actually changes quickly. An even spread made 20:30 in July look like midnight.
    enum Sky {
        /// One hour of the day: three gradient stops, and where the light is coming from.
        struct Stop {
            var hour: Double
            var top: Color
            var middle: Color
            var bottom: Color
            /// A soft bloom over the gradient — the sun, more or less, without pretending
            /// to know where it is.
            var glow: Color
            var glowAt: UnitPoint
            var glowStrength: Double
        }

        /// The one colour that stands for an hour, taken from the sky already written for it.
        ///
        /// The app was very nearly monochrome — a blue selection, an orange streak badge, and
        /// grey everywhere else — while carrying a whole gradient keyed to the time of day and
        /// using it in exactly one place. A session at four in the morning and a session after
        /// lunch are different in the one way this app is *about*, and nothing said so.
        ///
        /// The glow rather than the gradient: it is the most saturated part of a stop, and a
        /// four-point bar wants a colour rather than a wash. Nearest stop, not interpolated —
        /// this labels which part of the day a session fell in, and a boundary that slides is
        /// harder to read than one that steps.
        static func accent(atHour hour: Int, dark: Bool) -> Color {
            let stops = dark ? Self.dark : Self.light
            // `Stop.hour` is a Double — the stops are not all on whole hours, because the
            // sky does not change at an even rate and sunrise needs more of them than noon.
            let wrapped = Double(((hour % 24) + 24) % 24)
            let nearest = stops.min {
                abs($0.hour - wrapped) < abs($1.hour - wrapped)
            }
            guard let glow = nearest?.glow else { return .accentColor }
            // Lifted, because a wash and a hairline want opposite things from the same
            // colour. The stops are tuned for a gradient behind a whole card, where 16:30
            // is deliberately the washed-out one — saturation 0.33, value 0.48 — and at three
            // points wide that is not a colour, it is a smudge. The hue is the part that
            // carries the meaning; saturation and brightness only have to clear the floor.
            return glow.lifted(
                minimumSaturation: accentSaturation, minimumBrightness: accentBrightness
            )
        }

        /// Floors for ``accent(atHour:dark:)``. High enough to read at three points against a
        /// card, low enough not to shout over a page whose loudest element is a duration.
        static let accentSaturation: Double = 0.62
        static let accentBrightness: Double = 0.72

        /// How wide the bloom is, as a fraction of the frame's longer edge.
        static let glowRadius: Double = 0.85
        /// Where the bloom starts fading. Below this it is flat colour, which keeps the
        /// centre from reading as a disc.
        static let glowCore: Double = 0.10

        static let dark: [Stop] = [
            // Deep night.
            Stop(hour: 0,
                 top: Color(red: 0.030, green: 0.035, blue: 0.070),
                 middle: Color(red: 0.020, green: 0.025, blue: 0.050),
                 bottom: Color(red: 0.012, green: 0.015, blue: 0.030),
                 glow: Color(red: 0.10, green: 0.12, blue: 0.26),
                 glowAt: UnitPoint(x: 0.50, y: 0.95), glowStrength: 0.35),
            // The darkest stretch, just before anything happens.
            Stop(hour: 4.5,
                 top: Color(red: 0.035, green: 0.045, blue: 0.090),
                 middle: Color(red: 0.025, green: 0.030, blue: 0.060),
                 bottom: Color(red: 0.015, green: 0.018, blue: 0.035),
                 glow: Color(red: 0.12, green: 0.16, blue: 0.32),
                 glowAt: UnitPoint(x: 0.35, y: 0.95), glowStrength: 0.35),
            // First light: still cold above, warming at the horizon.
            Stop(hour: 6,
                 top: Color(red: 0.060, green: 0.080, blue: 0.170),
                 middle: Color(red: 0.090, green: 0.090, blue: 0.160),
                 bottom: Color(red: 0.130, green: 0.095, blue: 0.125),
                 glow: Color(red: 0.48, green: 0.30, blue: 0.28),
                 glowAt: UnitPoint(x: 0.28, y: 0.88), glowStrength: 0.38),
            // Sunrise. Early, and over quickly — by half past eight it is just morning.
            Stop(hour: 7,
                 top: Color(red: 0.080, green: 0.100, blue: 0.200),
                 middle: Color(red: 0.150, green: 0.115, blue: 0.180),
                 bottom: Color(red: 0.230, green: 0.135, blue: 0.125),
                 glow: Color(red: 0.72, green: 0.40, blue: 0.24),
                 glowAt: UnitPoint(x: 0.24, y: 0.84), glowStrength: 0.44),
            // Morning, opening out and turning cool.
            Stop(hour: 9,
                 top: Color(red: 0.065, green: 0.105, blue: 0.205),
                 middle: Color(red: 0.065, green: 0.115, blue: 0.215),
                 bottom: Color(red: 0.060, green: 0.120, blue: 0.210),
                 glow: Color(red: 0.22, green: 0.38, blue: 0.58),
                 glowAt: UnitPoint(x: 0.35, y: 0.72), glowStrength: 0.36),
            // Midday: the coolest and most open of them.
            Stop(hour: 13,
                 top: Color(red: 0.050, green: 0.100, blue: 0.190),
                 middle: Color(red: 0.050, green: 0.110, blue: 0.200),
                 bottom: Color(red: 0.040, green: 0.100, blue: 0.170),
                 glow: Color(red: 0.20, green: 0.40, blue: 0.62),
                 glowAt: UnitPoint(x: 0.50, y: 0.58), glowStrength: 0.38),
            // Late afternoon, warming and moving west.
            Stop(hour: 16.5,
                 top: Color(red: 0.070, green: 0.100, blue: 0.190),
                 middle: Color(red: 0.100, green: 0.100, blue: 0.190),
                 bottom: Color(red: 0.130, green: 0.100, blue: 0.170),
                 glow: Color(red: 0.42, green: 0.32, blue: 0.48),
                 glowAt: UnitPoint(x: 0.70, y: 0.68), glowStrength: 0.42),
            // Golden hour.
            Stop(hour: 18.5,
                 top: Color(red: 0.085, green: 0.080, blue: 0.180),
                 middle: Color(red: 0.150, green: 0.095, blue: 0.170),
                 bottom: Color(red: 0.205, green: 0.115, blue: 0.125),
                 glow: Color(red: 0.72, green: 0.42, blue: 0.22),
                 glowAt: UnitPoint(x: 0.80, y: 0.80), glowStrength: 0.40),
            // Sunset. The warmest the app ever gets — which is still not very, because a
            // full-window wash of orange is a screen you cannot read a title on.
            Stop(hour: 20,
                 top: Color(red: 0.090, green: 0.065, blue: 0.170),
                 middle: Color(red: 0.165, green: 0.080, blue: 0.165),
                 bottom: Color(red: 0.225, green: 0.085, blue: 0.130),
                 glow: Color(red: 0.70, green: 0.27, blue: 0.20),
                 glowAt: UnitPoint(x: 0.86, y: 0.88), glowStrength: 0.42),
            // Dusk, closing violet.
            Stop(hour: 21.5,
                 top: Color(red: 0.060, green: 0.045, blue: 0.135),
                 middle: Color(red: 0.090, green: 0.052, blue: 0.150),
                 bottom: Color(red: 0.115, green: 0.058, blue: 0.120),
                 glow: Color(red: 0.38, green: 0.16, blue: 0.30),
                 glowAt: UnitPoint(x: 0.90, y: 0.92), glowStrength: 0.34),
            // Night again — and back to the first stop, which is why 23 is not 0.
            Stop(hour: 23,
                 top: Color(red: 0.040, green: 0.040, blue: 0.090),
                 middle: Color(red: 0.030, green: 0.030, blue: 0.060),
                 bottom: Color(red: 0.020, green: 0.020, blue: 0.040),
                 glow: Color(red: 0.12, green: 0.13, blue: 0.26),
                 glowAt: UnitPoint(x: 0.60, y: 0.95), glowStrength: 0.34),
        ]

        /// The same day in a light room. Higher and flatter in luminance throughout, because
        /// the text over it is dark — a light sky has far less room to move than a dark one.
        static let light: [Stop] = [
            Stop(hour: 0,
                 top: Color(red: 0.62, green: 0.65, blue: 0.78),
                 middle: Color(red: 0.70, green: 0.72, blue: 0.83),
                 bottom: Color(red: 0.80, green: 0.81, blue: 0.88),
                 glow: Color(red: 0.50, green: 0.54, blue: 0.72),
                 glowAt: UnitPoint(x: 0.50, y: 0.95), glowStrength: 0.30),
            Stop(hour: 4.5,
                 top: Color(red: 0.66, green: 0.68, blue: 0.80),
                 middle: Color(red: 0.74, green: 0.75, blue: 0.85),
                 bottom: Color(red: 0.83, green: 0.84, blue: 0.90),
                 glow: Color(red: 0.55, green: 0.58, blue: 0.75),
                 glowAt: UnitPoint(x: 0.35, y: 0.95), glowStrength: 0.30),
            Stop(hour: 6,
                 top: Color(red: 0.80, green: 0.82, blue: 0.92),
                 middle: Color(red: 0.92, green: 0.87, blue: 0.87),
                 bottom: Color(red: 0.97, green: 0.89, blue: 0.83),
                 glow: Color(red: 0.99, green: 0.78, blue: 0.62),
                 glowAt: UnitPoint(x: 0.28, y: 0.88), glowStrength: 0.50),
            Stop(hour: 7,
                 top: Color(red: 0.84, green: 0.87, blue: 0.95),
                 middle: Color(red: 0.96, green: 0.88, blue: 0.84),
                 bottom: Color(red: 0.99, green: 0.86, blue: 0.75),
                 glow: Color(red: 1.00, green: 0.72, blue: 0.48),
                 glowAt: UnitPoint(x: 0.24, y: 0.84), glowStrength: 0.62),
            Stop(hour: 9,
                 top: Color(red: 0.80, green: 0.88, blue: 0.97),
                 middle: Color(red: 0.88, green: 0.93, blue: 0.98),
                 bottom: Color(red: 0.95, green: 0.96, blue: 0.99),
                 glow: Color(red: 0.78, green: 0.90, blue: 1.00),
                 glowAt: UnitPoint(x: 0.35, y: 0.72), glowStrength: 0.40),
            Stop(hour: 13,
                 top: Color(red: 0.78, green: 0.87, blue: 0.98),
                 middle: Color(red: 0.87, green: 0.92, blue: 0.99),
                 bottom: Color(red: 0.95, green: 0.97, blue: 1.00),
                 glow: Color(red: 0.80, green: 0.91, blue: 1.00),
                 glowAt: UnitPoint(x: 0.50, y: 0.58), glowStrength: 0.36),
            Stop(hour: 16.5,
                 top: Color(red: 0.84, green: 0.87, blue: 0.96),
                 middle: Color(red: 0.91, green: 0.90, blue: 0.95),
                 bottom: Color(red: 0.96, green: 0.93, blue: 0.94),
                 glow: Color(red: 0.94, green: 0.86, blue: 0.92),
                 glowAt: UnitPoint(x: 0.70, y: 0.68), glowStrength: 0.40),
            Stop(hour: 18.5,
                 top: Color(red: 0.86, green: 0.85, blue: 0.94),
                 middle: Color(red: 0.96, green: 0.87, blue: 0.85),
                 bottom: Color(red: 0.99, green: 0.87, blue: 0.77),
                 glow: Color(red: 1.00, green: 0.78, blue: 0.52),
                 glowAt: UnitPoint(x: 0.80, y: 0.80), glowStrength: 0.60),
            Stop(hour: 20,
                 top: Color(red: 0.82, green: 0.80, blue: 0.92),
                 middle: Color(red: 0.95, green: 0.83, blue: 0.83),
                 bottom: Color(red: 0.98, green: 0.82, blue: 0.76),
                 glow: Color(red: 1.00, green: 0.64, blue: 0.50),
                 glowAt: UnitPoint(x: 0.86, y: 0.88), glowStrength: 0.62),
            Stop(hour: 21.5,
                 top: Color(red: 0.72, green: 0.72, blue: 0.86),
                 middle: Color(red: 0.83, green: 0.78, blue: 0.87),
                 bottom: Color(red: 0.90, green: 0.85, blue: 0.89),
                 glow: Color(red: 0.86, green: 0.62, blue: 0.76),
                 glowAt: UnitPoint(x: 0.90, y: 0.92), glowStrength: 0.44),
            Stop(hour: 23,
                 top: Color(red: 0.64, green: 0.66, blue: 0.79),
                 middle: Color(red: 0.72, green: 0.73, blue: 0.84),
                 bottom: Color(red: 0.82, green: 0.82, blue: 0.88),
                 glow: Color(red: 0.52, green: 0.55, blue: 0.73),
                 glowAt: UnitPoint(x: 0.60, y: 0.95), glowStrength: 0.32),
        ]

        /// The flat surface Reduce Transparency gets instead.
        static let flatDark = Color(red: 0.020, green: 0.022, blue: 0.040)
        static let flatLight = Color(white: 0.96)
    }

    // ── elevation, blur, shadow ───────────────────────────────────────────────

    /// How far a surface sits from the page.
    ///
    /// Kept to three levels on purpose. A window this dense with cards turns any more into
    /// noise, and macOS itself separates with material and hairlines far more than shadow.
    enum Elevation {
        /// Flush: a row in a list.
        case flat
        /// Lifted: a card the eye should read as an object.
        case raised
        /// Floating: a sheet or popover over content.
        case floating

        var shadowRadius: CGFloat {
            switch self {
            case .flat: 0
            case .raised: 3
            case .floating: 24
            }
        }

        var shadowOpacity: Double {
            switch self {
            case .flat: 0
            case .raised: 0.10
            case .floating: 0.28
            }
        }

        var shadowOffsetY: CGFloat {
            switch self {
            case .flat: 0
            case .raised: 1
            case .floating: 10
            }
        }
    }

    /// System materials, named for where they belong rather than by thickness.
    enum Material {
        /// Behind a sheet's content.
        static let sheet: SwiftUI.Material = .regular
        /// A bar that content scrolls under.
        static let bar: SwiftUI.Material = .bar
        /// A floating panel over the window.
        static let panel: SwiftUI.Material = .thick
    }

    // ── icons ─────────────────────────────────────────────────────────────────

    /// App icon sizes. Named for context because an icon's size is decided by what it sits
    /// beside, never by preference.
    enum Icon {
        /// The column every sidebar glyph is centred in, so the names beside them line up.
        /// SF Symbols are not one width, and a `Label` sizes its icon to the glyph.
        static let sidebarColumn: CGFloat = 18

        /// In a dense app-breakdown row.
        static let inline: CGFloat = 18
        /// In a search result or an exclusion list.
        static let listItem: CGFloat = 20
        /// The stack on a session card.
        static let stack: CGFloat = 22
        /// Beside a headline figure.
        static let feature: CGFloat = 26
        /// A progress ring on Today.
        static let ring: CGFloat = 38
        /// A category glyph's column in a collection row, so labels align down the list.
        static let glyphColumn: CGFloat = 26
        /// An application at the head of its own history page.
        static let appHeader: CGFloat = 64
        /// An application's own icon in the Apps list, where it is the row's subject.
        static let appRow: CGFloat = 36
        /// The stack on a session, and one favourite, in the screensaver — larger, because
        /// it is read from further away.
        static let screensaverStack: CGFloat = 32
        static let screensaverFavourite: CGFloat = 44
        /// The app you are being offered to return to, on the resume card.
        static let resume: CGFloat = 48
        /// The app's own icon, on the welcome screen.
        static let welcomeMark: CGFloat = 72
        /// The application at the centre of a moment being played back.
        static let playbackMark: CGFloat = 112
        /// The app's own icon, in About.
        static let about: CGFloat = 64
        /// A tinted tile in the Settings source list.
        static let settingsTile: CGFloat = 20
    }

    // ── layout ────────────────────────────────────────────────────────────────

    enum Layout {
        /// The main window's default size: a sidebar plus a detail column wide enough for
        /// the readable measure below, rather than the pre-sidebar width with a column
        /// carved out of it.
        static let windowWidth: CGFloat = 980
        static let windowHeight: CGFloat = 760
        static let windowMinWidth: CGFloat = 720
        static let windowMinHeight: CGFloat = 480
        /// The width an Xcode `#Preview` gives a card, so the canvas shows it at roughly the
        /// measure it has in the detail column rather than shrink-wrapped to its content.
        /// Ships in the binary and costs nothing; previews are compiled out of release
        /// builds by the `#if DEBUG` around them.
        static let previewWidth: CGFloat = 520
        /// The leading inset a sidebar `List` gives its own rows, matched by anything laid
        /// out beside it rather than inside it — the footer, which otherwise sat two points
        /// to the left of every row above it.
        ///
        /// A measured number, not a chosen one: SwiftUI does not publish the inset it uses,
        /// so this is where the list's own labels actually start, read off a screenshot of
        /// the running app. Worth re-measuring if a macOS release moves the source list
        /// about; the check is that one straight edge runs down every label in the sidebar.
        static let sidebarRowInset: CGFloat = 20
        /// The sidebar. A range rather than a number, because a split view lets the user
        /// decide and only needs to be told what is sensible.
        static let sidebarMinWidth: CGFloat = 170
        static let sidebarWidth: CGFloat = 200
        static let sidebarMaxWidth: CGFloat = 260

        /// Settings: a source list and a pane, as System Settings is.
        static let settingsWidth: CGFloat = 720
        static let settingsHeight: CGFloat = 520
        static let settingsSidebarWidth: CGFloat = 190
        static let settingsDetailWidth: CGFloat = 480
        /// A sheet that lists things — the exclusion picker.
        static let sheetWidth: CGFloat = 460
        static let sheetHeight: CGFloat = 420

        /// The widest a column of *text* is allowed to get. Beyond this a line is tiring to
        /// read, however wide the window is. This is the measure for prose — the
        /// autobiography, the museum, the legacy — and the three of them apply it to their
        /// own paragraphs, inside whatever width the page gives them.
        static let readableWidth: CGFloat = 760
        /// The widest a *page* is allowed to get, which is a different question.
        ///
        /// A page here is cards: a headline, a row of figures, sessions with a duration on
        /// the right. None of that is a line of prose, and holding it to the prose measure
        /// was what put a dead column against the scroll bar on a wide window. So the page
        /// grows with the window and stops here, which at a maximised 1500pt leaves a real
        /// margin either side rather than a gap on one.
        ///
        /// There is no matching minimum because the window already has one: 720pt of window
        /// less a 170pt sidebar and the page gutter still leaves a column wider than the
        /// widest card minimum, so nothing here can be squeezed into overlapping.
        static let pageWidth: CGFloat = 1080

        /// The narrowest one of Today's secondary cards may be before the row folds to one.
        ///
        /// Today used to be a single column of full-width cards, and at the default window
        /// that meant a 1080pt slab holding about 350pt of text — "9h 47m active, mostly
        /// Terminal" stretched across the page with the right half of it empty. The cards
        /// that *comment* on the day — the goal, the briefing, a memory, the hero — are short
        /// and unrelated to each other, so they sit two abreast; the ones that *are* the day
        /// — the headline and the session list — still run full width.
        static let todaySecondaryMinimum: CGFloat = 420

        /// The bar down the leading edge of a session, in the colour of the hour it began.
        /// How much history the heatmap wants before it opens on a wider range. Not the
        /// length of each range but the point at which the next one up stops being mostly
        /// empty — a fortnight in a month grid reads; a fortnight in a year grid does not.
        static let heatmapWeekDays = 14
        static let heatmapMonthDays = 70

        static let accentBarWidth: CGFloat = 3
        static let accentBarHeight: CGFloat = 32

        /// `.adaptive`, so a narrow window folds to one column on its own rather than needing
        /// a size class or a breakpoint to be chosen for it.
        static let todaySecondaryColumns = [
            GridItem(.adaptive(minimum: todaySecondaryMinimum), spacing: Space.block)
        ]
        /// The welcome screen's column, and its page dots.
        static let welcomeWidth: CGFloat = 520
        /// The What's New window, and the dot in front of one of its lines.
        /// Playing a day back: the marks on the filmstrip, the playhead, the speed control.
        static let filmstripMark: CGFloat = 3
        static let playhead: CGFloat = 10
        /// A round close button over a full-window surface. The whole disc is the target.
        static let closeButton: CGFloat = 34
        /// Ambient mode, for a second monitor across a room. The headline is clamped rather
        /// than fixed — the reference scales it with the viewport between 72 and 180 — and
        /// the icon is large enough to recognise from a desk away.
        static let ambientHeadlineMin: CGFloat = 72
        static let ambientHeadlineMax: CGFloat = 180
        static let ambientHeadlineShare: CGFloat = 0.15
        static let ambientIcon: CGFloat = 56
        static let ambientNowTitle: CGFloat = 26
        static let ambientEyebrowKerning: CGFloat = 3.0
        static let ambientNowKerning: CGFloat = 1.6
        /// The gap between the headline and what is happening now. Generous on purpose:
        /// this is read from across a room, and at that distance ordinary spacing reads as
        /// one block of text rather than as two things.
        static let ambientGap: CGFloat = 56
        /// The clock above the day's total. Big enough to read from where the screen is,
        /// small enough that the figure underneath is still the headline — this is a display
        /// you glance at, and on a glance the question is usually "what time is it".
        static let ambientClock: CGFloat = 40
        /// The screensaver's clock. Smaller than ambient mode's, because that screen is
        /// *for* being read and this one is passed by — big enough to catch from a doorway,
        /// small enough not to become the thing on screen.
        static let screensaverClock: CGFloat = 30
        static let playbackSpeedWidth: CGFloat = 130
        static let whatsNewWidth: CGFloat = 620
        static let whatsNewHeight: CGFloat = 560
        static let bulletSize: CGFloat = 4
        static let welcomeDot: CGFloat = 7

        /// The least width a card in a grid gets before the grid drops to one column.
        static let cardMinWidth: CGFloat = 320
        /// A settings row's control column, so labels and controls align down the page.
        static let settingsControlGap: CGFloat = 16
        /// The width an app name is given in an app-breakdown row, so bars line up.
        static let appNameColumn: CGFloat = 150
        /// And the duration at its end.
        static let durationColumn: CGFloat = 56

        /// A progress bar's thickness.
        static let barThickness: CGFloat = 4
        /// A thinner one, under a row that already carries its own figures.
        static let barThin: CGFloat = 3
        /// The least of a bar that ever draws, so a sliver of time is still visible.
        static let barMinFraction: Double = 0.04
        /// A segmented control, kept to its content rather than stretched down the page.
        static let segmentedWidth: CGFloat = 320
        /// A rule between sections.
        static let hairline: CGFloat = 1
        /// The prominent search field at the head of the Search surface.
        static let searchFieldHeight: CGFloat = 44
        /// A progress ring's stroke.
        static let ringThickness: CGFloat = 4
        /// The row a progress bar is laid out in.
        static let barRow: CGFloat = 12
        /// The filmstrip's *hit* height, which is not its drawn height.
        ///
        /// Apple's gesture guidance asks for about ten points of slack around a small
        /// target; a 12-point bar is a 12-point bar to the eye and a coin-toss to the
        /// pointer. The bar stays 12 and the grabbable band around it is this, which is the
        /// same trick the close button on this screen already uses — "the hit area is the
        /// whole disc, not the glyph inside it."
        static let barHitRow: CGFloat = 32
        /// How much bigger the playhead gets while it is being dragged.
        ///
        /// Response, in Apple's sense: the scrubber answered a drag by moving the playhead
        /// and said nothing at all about being *held*, so a drag that started outside the
        /// bar and a drag that started on it looked identical. It grows on pointer-down —
        /// not on release — because the moment feedback waits for the mouse-up is the
        /// moment directness falls off a cliff.
        static let playheadGrabScale: CGFloat = 1.45
        /// A weekday's name and date, so the seven rhythm rows align.
        static let weekdayColumn: CGFloat = 44
        /// A day's rhythm strip, and the pieces of it.
        static let arcHeight: CGFloat = 28
        /// A quiet hour still draws, so the shape of a day stays legible.
        static let arcBaseline: CGFloat = 2
        /// And an hour with anything in it is never thinner than this.
        static let arcMinBar: CGFloat = 3.4
        /// A bar is measured against a sixth of the busiest day…
        static let arcCeilingDivisor: Double = 6
        /// …but never against less than ten minutes, or a week of short days draws full.
        static let arcCeilingFloorSeconds: Double = 600
        /// The hour scale under the seven rows.
        static let axisHeight: CGFloat = 12
        /// The canvas: how big a node gets, how far it can be zoomed, and how forgiving a
        /// click on one is.
        static let canvasMinRadius: CGFloat = 7
        static let canvasMaxRadius: CGFloat = 34
        static let canvasRadiusScale: CGFloat = 0.22
        static let canvasMomentRadius: CGFloat = 5
        static let canvasCollectionRadius: CGFloat = 26
        static let canvasEdgeWidth: CGFloat = 1
        static let canvasSelectionInset: CGFloat = 3
        static let canvasSelectionWidth: CGFloat = 2
        /// Below this drawn radius a label is noise rather than information.
        static let canvasLabelThreshold: CGFloat = 9
        /// And below this one an icon is a smudge, so the node stays a plain dot.
        static let canvasIconThreshold: CGFloat = 8
        /// The size icons are rasterised at, once. Large enough that the deepest zoom is
        /// still downscaling rather than stretching.
        /// How much of a node's disc is padding around what is in it, as a fraction of its
        /// radius. Every node is a bubble *containing* something rather than a circle cut
        /// out of it — which is what a full-bleed clip did to a squircle app icon and to a
        /// collection's glyph, both of which ran into their own ring.
        /// A colour choice in Settings, and the ring that marks the chosen one.
        static let swatch: CGFloat = 20
        static let swatchRing: CGFloat = 1.5
        static let swatchRingGap: CGFloat = 3

        static let canvasIconInset: CGFloat = 0.20
        /// The size each icon is rasterised at for the field.
        ///
        /// Large enough that the biggest node at the deepest zoom is still scaling an image
        /// *down*: `canvasMaxRadius × 2 × canvasMaxZoom`. At 96 it was upscaling roughly
        /// twofold once anyone zoomed in, which is exactly when the icon is worth looking
        /// at. Affordable only because the symbols are keyed on the icon rather than on the
        /// node — a dozen nodes wearing one application's face share one raster.
        static let canvasSymbolSize: CGFloat = 204
        /// A badge on a node that wears another thing's icon, and the glyph inside it.
        static let canvasBadgeRadius: CGFloat = 7
        static let canvasBadgeGlyph: CGFloat = 8
        /// Padding around a label when deciding whether two of them collide.
        static let canvasLabelPadding: CGFloat = 4
        /// The ring that keeps a node's kind legible once its face is an app icon.
        static let canvasRingWidth: CGFloat = 2
        static let canvasRingWidthStrong: CGFloat = 3
        static let canvasHitSlack: CGFloat = 6
        /// How far out and in the field goes. The reference's, and checked: this port had
        /// 0.4, which sounds like the same number and is a whole view of a large history
        /// you could not reach.
        /// Where applications start fading, and where their names appear. Two thresholds
        /// rather than one because they answer different questions — how far out before an
        /// application stops being the point, and how far in before there is room for its
        /// name. Both the reference's.
        static let canvasAppsFadedBelowZoom: CGFloat = 0.7
        static let canvasAppLabelsFromZoom: CGFloat = 1.15
        static let canvasMinZoom: CGFloat = 0.32
        static let canvasMaxZoom: CGFloat = 3
        static let canvasPreviewWidth: CGFloat = 300
        /// The timeline beside the canvas. Wide enough for a session's name and its hours
        /// on one line each, and no wider — it is a companion to the field, not a rival.
        static let canvasPanelWidth: CGFloat = 300
        /// The command palette: wide enough for a sentence of a subtitle, tall enough for a
        /// handful of results without becoming a window of its own.
        static let paletteWidth: CGFloat = 560
        static let paletteMaxHeight: CGFloat = 380
        static let paletteShadowRadius: CGFloat = 30
        static let paletteShadowOffset: CGFloat = 12
        static let paletteTopInset: CGFloat = 120
        /// Release notes in a popover. Narrower than the palette because these are lines of
        /// prose rather than rows, and capped rather than fixed: most releases are four
        /// bullets, and a box sized for the worst case is mostly empty for the usual one.
        /// The menu bar popover. Narrow on purpose: it is read in the corner of the screen
        /// while something else has your attention, and a panel wide enough to browse is a
        /// panel you stop to read. Everything in it fits without scrolling at this width.
        static let menuBarPopoverWidth: CGFloat = 288
        /// The quick-note panel. Wider than the menu bar panel it is opened from, because
        /// this one holds a sentence rather than a column of figures — and narrower than any
        /// window, because it is one field and two buttons.
        static let notePanelWidth: CGFloat = 360
        /// The goal bar inside it — a bar rather than Today's ring, which needs room to
        /// anchor and becomes a thin circle read at a glance at this size. Four points
        /// rather than six: at six a full green bar read as an alert rather than a
        /// measurement, and thinning it was worth more than muting the colour.
        static let menuBarGoalBar: CGFloat = 4
        /// The duration column on a PDF row, wide enough for "10h 30m".
        static let pdfDurationColumn: CGFloat = 52
        static let releaseNotesWidth: CGFloat = 420
        static let releaseNotesMaxHeight: CGFloat = 340
        /// A year of days as a grid. How *many* weeks it draws is the reference's own
        /// `Heatmap.yearWeeks` and is contract-checked; these are how big it renders.
        static let heatmapSquare: CGFloat = 11
        static let heatmapGap: CGFloat = 3
        /// The gutter the month labels sit above, which is the weekday column's width.
        static let heatmapWeekdayColumn: CGFloat = 18
        /// A month's cells are large enough to carry a date, and a week's larger still to
        /// carry a duration — the same grid at three magnifications, not three components.
        static let heatmapMonthCell: CGFloat = 34
        static let heatmapWeekCell: CGFloat = 62
        /// The ring on today, so the grid says where you are without a caption.
        static let heatmapTodayRing: CGFloat = 1.5
        /// One press of zoom in or out. A ratio rather than a step, so each press feels the
        /// same however far in you already are.
        static let canvasZoomStep: CGFloat = 1.2
        /// How far a click may wander before it becomes a drag.
        static let canvasClickSlop: CGFloat = 4
        /// Zoom by scrolling, in the two shapes the reference has. A trackpad's precise
        /// deltas are continuous, so they go through an exponential and the field zooms as
        /// smoothly as the fingers move; a wheel arrives in notches and gets one firm step
        /// each. Upstream the smooth path is a pinch — a browser reports one as a wheel
        /// event — and this port already has pinch as a real gesture, so what it maps to
        /// here is two-finger scrolling.
        static let canvasWheelSensitivity: CGFloat = 0.012
        static let canvasWheelStep: CGFloat = 1.09
        /// The magnification readout, wide enough for "300%" so the toolbar does not shuffle.
        static let canvasZoomReadoutWidth: CGFloat = 44
        /// Where a double-click lands you: close enough to read a node's neighbourhood.
        static let canvasFocusZoom: CGFloat = 1.55
        /// Where the tour lands: further in at its middle stops than at either end, so
        /// arriving and leaving frame the neighbourhood and the stops between it read one
        /// thing at a time.
        static let canvasTourEndZoom: CGFloat = 1.5
        static let canvasTourStepZoom: CGFloat = 1.9
        /// A flick keeps gliding, decaying to rest.
        ///
        /// The decay is per *frame* upstream, which is a real quirk: it is applied inside a
        /// `requestAnimationFrame` loop, so the same flick coasts further on a 60 Hz display
        /// than on a 120 Hz one. Reproducing the quirk would be the wrong kind of fidelity,
        /// so the port keeps the reference's number and reads it as the 60 Hz rate it was
        /// written against — see `canvasGlideHalfLife`.
        static let canvasGlideDecay: CGFloat = 0.9
        static let canvasGlideReferenceHz: CGFloat = 60
        static let canvasGlideMinSpeed: CGFloat = 2
        static let canvasGlideRestSpeed: CGFloat = 0.4
        /// The screensaver's column, and how far its edges dissolve.
        static let screensaverColumnWidth: CGFloat = 460
        static let screensaverFade: CGFloat = 160
        /// A small numeric field in Settings.
        static let numberField: CGFloat = 60
        /// A tag entry field, sized to a tag rather than to the row.
        static let tagField: CGFloat = 90
    }
}

// ── the tokens, applied ───────────────────────────────────────────────────────

extension EnvironmentValues {
    /// How this view should move, given what the user has asked the system for.
    var motion: Design.MotionPreference {
        Design.MotionPreference(reduced: accessibilityReduceMotion)
    }

}

extension View {
    /// A card: the app's fundamental container.
    ///
    /// One modifier rather than a background, an overlay and a radius repeated in nine
    /// files — which is what this replaced, and how the surfaces had already drifted a
    /// point or two apart from each other.
    func card(
        radius: CGFloat = Design.Radius.card,
        elevation: Design.Elevation = .flat,
        background: AnyShapeStyle = Design.Colour.surfaceQuiet,
        border: AnyShapeStyle? = Design.Colour.border
    ) -> some View {
        modifier(Card(radius: radius, elevation: elevation, background: background, border: border))
    }

    /// An uppercase section label — the app's one piece of typographic furniture.
    func sectionLabelStyle() -> some View {
        self
            .font(Design.Text.sectionLabel)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(Design.Text.labelKerning)
    }

    /// The smaller label used inside a card.
    func cardLabelStyle() -> some View {
        self
            .font(Design.Text.cardLabel)
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .kerning(Design.Text.labelKerning)
    }

    /// A card settling as it comes into view.
    ///
    /// A `scrollTransition` rather than an entrance animation, because the content is a
    /// list of someone's day: rows arrive as they are scrolled to, not all at once on
    /// appear, and the effect has to be undetectable when you are reading rather than
    /// scrolling. Nothing moves — only opacity and a fraction of a point of scale, which
    /// reads as depth rather than as animation.
    func settlesIntoView(reduced: Bool) -> some View {
        modifier(SettlesIn(index: 0))
    }

    /// A section arriving, and then behaving as it scrolls.
    ///
    /// Two things at once, because they are the same idea at different moments. On open the
    /// section rises a little and fades in, staggered by its position so a screen assembles
    /// top-down rather than appearing whole — which is what makes a surface feel *entered*
    /// rather than switched to. As it scrolls, the same content dims slightly at the edges.
    ///
    /// The stagger is capped, so a long page finishes arriving rather than trickling in for
    /// seconds, and Reduce Motion skips the whole thing: someone who asked the system to
    /// stop moving things did not ask for a shorter movement.
    func settlesIn(_ index: Int = 0) -> some View {
        modifier(SettlesIn(index: index))
    }

    /// The same arrival, on a search result's faster clock.
    ///
    /// A separate entry point rather than a parameter with a default, so the two staggers
    /// stay two decisions: reaching for this is choosing the one the reference reserves for
    /// results, and the compiler will not let it happen by accident.
    func settlesInAsResult(_ index: Int) -> some View {
        modifier(SettlesIn(index: index, delay: Design.Motion.resultDelay(index)))
    }



    /// Content that should sit in the middle of whatever room it has, rather than at the
    /// left edge of a measure that is narrower than the window.
    ///
    /// An empty state is the whole screen when it is showing. Constraining it to the
    /// reading measure and then aligning that measure left put it a third of the way across
    /// a wide window, which reads as a layout mistake rather than as emptiness.
    func centredInPage() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A page's scrolling content: one gutter, one rhythm, one measure, every surface.
    ///
    /// The measure matters more since the window gained a sidebar. Without it a card runs
    /// the full width of a maximised display, and a line of forty words is tiring to read
    /// however much room there is for it.
    ///
    /// **It grows with the window, and it is centred.** Two things were wrong and they hid
    /// each other. The cap was the *prose* measure, 760pt, applied to pages that are cards
    /// rather than paragraphs; and the column was pinned to `.topLeading`, so every pixel of
    /// slack collected on one side. Widening the window grew a dead strip against the scroll
    /// bar, and the page read as content that had failed to load. Now the page takes the
    /// width it is given up to `pageWidth`, and what is left over is split into two margins.
    /// Prose is unaffected: the three surfaces that have any hold their own paragraphs to
    /// `readableWidth` inside this, which is where that limit belongs.
    /// A paragraph, held to the measure a paragraph wants.
    ///
    /// The page grows with the window; a sentence must not. Without this the day's story ran
    /// the full width of a maximised page — a hundred and fifty characters to a line, which
    /// is the length at which the eye loses its place coming back for the next one. Use it on
    /// narrative text that sits inside a card, since the card is right to be as wide as the
    /// page and the text inside it is not.
    func proseColumn() -> some View {
        frame(maxWidth: Design.Layout.readableWidth, alignment: .leading)
    }

    func pageContent() -> some View {
        self
            .padding(Design.Space.page)
            .frame(maxWidth: Design.Layout.pageWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}

/// What a card is made of.
///
/// The choice is the user's because it is a matter of taste and of legibility, and the two do
/// not always agree: glass is lovely over a photograph and can be tiring over a dense list.
/// The default is glass, since that is what the system does now, but a flat surface is a
/// first-class option rather than a fallback.
private struct Card: ViewModifier {
    let radius: CGFloat
    let elevation: Design.Elevation
    let background: AnyShapeStyle
    let border: AnyShapeStyle?

    @Environment(\.surfaceStyle) private var style
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // Reduce Transparency is not a preference to weigh against the setting — it is a
        // statement that blur is a problem, so it wins outright.
        // `drawable` first, so a Mac that cannot draw glass resolves to frosted *here* —
        // which also means the border logic below sees frosted and draws its edge, rather
        // than omitting it for a pane that has no glass edge of its own.
        let resolved: SurfaceStyle = reduceTransparency ? .solid : style.drawable
        return Group {
            switch resolved {
            case .solid:
                content.background(background, in: shape)
            case .frosted:
                content.background(.regularMaterial, in: shape)
            case .glass:
                // Unreachable below macOS 26 — `drawable` has already turned it to frosted —
                // but the compiler needs the guard, and an `if #available` reads better than
                // an unavailable branch that only a comment says is dead.
                if #available(macOS 26, *) {
                    content.glassEffect(.regular, in: shape)
                } else {
                    content.background(.regularMaterial, in: shape)
                }
            }
        }
        .overlay {
            if let border {
                // Glass carries its own edge; a drawn border on top of it reads as a box
                // around a pane rather than as the pane itself.
                if resolved != .glass {
                    shape.strokeBorder(border, lineWidth: Design.Layout.hairline)
                }
            }
        }
        .shadow(
            color: .black.opacity(elevation.shadowOpacity),
            radius: elevation.shadowRadius,
            y: elevation.shadowOffsetY
        )
    }
}

/// How every surface in the app is drawn.
enum SurfaceStyle: String, CaseIterable, Identifiable, Sendable {
    /// A plain tinted fill. Cheapest to draw and the easiest to read over.
    case solid
    /// The system's blur. Depth without the specular edge.
    case frosted
    /// The system's own glass — the current macOS material.
    case glass

    var id: String { rawValue }

    /// Whether this Mac can draw the system's glass at all.
    ///
    /// `glassEffect` arrived in macOS 26 and is the *only* thing in this app that needs it —
    /// measured by building the whole package against macOS 14, which produced two errors,
    /// both here. Everything else works three OS generations back.
    static var glassAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    /// The styles worth offering on this Mac.
    ///
    /// Glass is left out where it cannot be drawn rather than shown and quietly substituted.
    /// A setting that does nothing is worse than a setting that is not there: the first makes
    /// somebody wonder whether their Mac is broken, the second tells them the truth by
    /// omission.
    static var offered: [SurfaceStyle] {
        glassAvailable ? allCases : [.solid, .frosted]
    }

    /// What this style actually draws as here.
    ///
    /// A preference set on a newer Mac travels — in a backup, or on the same account — so a
    /// stored `glass` has to mean something on a Mac that cannot draw it. Frosted, which is
    /// the nearest thing and already one of the choices.
    var drawable: SurfaceStyle {
        self == .glass && !Self.glassAvailable ? .frosted : self
    }

    var label: String {
        switch self {
        case .solid: Loc.t("Solid")
        case .frosted: Loc.t("Frosted")
        case .glass: Loc.t("Glass")
        }
    }

    /// Translated here, and the caller composes verbatim.
    ///
    /// It has to be this way round. Only the *selected* style's line is ever shown, so the
    /// runtime key recorder can see at most one of the three, and the source scanner finds
    /// keys by looking for `Loc.t("…")` — so a bare literal here would leave two of them
    /// invisible to both, and a language would report complete while missing them.
    var detail: String {
        switch self {
        case .solid: Loc.t("A flat surface. The quietest, and the easiest to read over.")
        case .frosted: Loc.t("Blurred, with depth but no shine.")
        case .glass: Loc.t("The system's own material, with its edge and its light.")
        }
    }
}

extension EnvironmentValues {
    /// Set once at the root from the preference, so every card reads the same answer.
    @Entry var surfaceStyle: SurfaceStyle = .glass

    /// The app's tint, resolved to a concrete colour.
    ///
    /// Almost everything reads the tint as a *style* (`.tint`), which `.tint(_:)` at the
    /// root already carries. This exists for the handful of places that cannot: a `Canvas`
    /// fills with a `Color`, and `AnyShapeStyle(Color.accentColor)` is baked at the point it
    /// is written rather than resolved from the environment.
    @Entry var themeTint: Color = .accentColor
}

/// A row or card that answers being pointed at and being pressed.
///
/// The app had neither, anywhere. Every list row, session card, memory and search result was
/// a `.plain` button: it opened something when clicked and gave no sign at all that it was
/// the kind of thing that could be clicked, or that the click had landed. The reference has
/// both on all of them — `hover:bg-control-subtle` and `active:scale-[0.99]` with
/// `active:bg-control`, on `--replay-ease-standard`, which is this file's `easeStandard` to
/// the fourth decimal.
///
/// Worth naming how it went unnoticed: `Design.Motion.press` has been in this file from the
/// beginning, is mirrored into `ParityKit`, and is checked every run against the reference's
/// own `pressMs: 90`. Nothing used it. The contract was green on a value the app never
/// applied — a check can only tell you two numbers agree, never that either is reaching a
/// person.
///
/// The two timings are different on purpose, and the asymmetry is the reference's: pressing
/// registers in 90ms because it is answering you, and settling back into hover takes 180
/// because nothing is waiting on that.
struct RowButtonStyle: ButtonStyle {
    /// Matched to the row's own corner so the highlight sits inside it rather than proud of
    /// it. A card and a bare list row do not share a radius, so it is asked for.
    var radius: CGFloat = Design.Radius.card

    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, radius: radius)
    }

    /// A `View` rather than the style's own body, because a style cannot hold `@State` and
    /// hover is state.
    private struct Surface: View {
        let configuration: Configuration
        let radius: CGFloat

        @Environment(\.motion) private var motion
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(fill)
                )
                // Reduced motion keeps the highlight and drops the give: the colour is what
                // says "this is pressable", and the scale is the part that is movement.
                .scaleEffect(
                    configuration.isPressed && !motion.reduced ? Design.Motion.pressScale : 1
                )
                .animation(
                    motion.animation(configuration.isPressed
                        ? Design.Motion.press
                        : Design.Motion.inPlace),
                    value: configuration.isPressed
                )
                .animation(motion.animation(Design.Motion.inPlace), value: hovering)
                .onHover { hovering = $0 }
        }

        private var fill: AnyShapeStyle {
            if configuration.isPressed { return Design.Colour.rowPressed }
            return hovering ? Design.Colour.rowHover : AnyShapeStyle(.clear)
        }
    }
}

extension ButtonStyle where Self == RowButtonStyle {
    /// A pressable row at the standard card radius.
    static var row: RowButtonStyle { RowButtonStyle() }
    /// A pressable row whose corner is not the standard one.
    static func row(radius: CGFloat) -> RowButtonStyle { RowButtonStyle(radius: radius) }
}

private struct SettlesIn: ViewModifier {
    let index: Int
    /// When this one arrives. `nil` takes the app's general stagger from its index.
    var delay: Double?

    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var arrived = false

    func body(content: Content) -> some View {
        content
            .opacity(reduced || arrived ? 1 : 0)
            .offset(y: reduced || arrived ? 0 : Design.Motion.enterRise)
            .onAppear {
                guard !reduced else { return }
                withAnimation(
                    Design.Motion.enter.delay(delay ?? Design.Motion.enterDelay(index))
                ) {
                    arrived = true
                }
            }
            // `reduced` is read once, here, rather than inside the closure: the transition
            // body is `Sendable` and the environment value is main-actor isolated, which
            // Swift 6 warns about eight times over. A plain `Bool` crosses freely.
            .scrollTransition(.interactive, axis: .vertical) { [still = reduced] content, phase in
                content
                    .opacity(still ? 1 : (phase.isIdentity ? 1 : Design.Motion.scrollFade))
                    .scaleEffect(still ? 1 : (phase.isIdentity ? 1 : Design.Motion.scrollShrink))
            }
    }
}

// ── the theme, on every window ────────────────────────────────────────────────

/// Wraps a window's content so it follows the chosen appearance and tint.
///
/// A `View` rather than a modifier, and that distinction is the whole point. Each auxiliary
/// window is its own `NSHostingController` whose `rootView` is built once, outside any body —
/// so `.tint(preferences.themeColour.colour)` written there reads the preference at
/// construction and never again. Picking a colour ringed the new swatch and changed nothing.
/// Inside a body, the same read is an observation, and every window follows.
@MainActor
struct Themed<Content: View>: View {
    let preferences: Preferences
    /// A scheme this window insists on, whatever the setting says. Only the two full-screen
    /// displays use it: they are black by design, and "Theme: Light" is not an instruction to
    /// put a white sheet over the whole screen at midnight.
    var forcing: ColorScheme?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .tint(preferences.themeColour.colour)
            .environment(\.themeTint, preferences.themeColour.resolved)
            .environment(\.surfaceStyle, preferences.surfaceStyle)
            // The appearance belongs here rather than in each window, and that is a fix.
            //
            // It used to be applied by `RootView` and by the menu bar panel, which are two of
            // the six windows this app opens — so with Theme set to Light, **Settings, What's
            // New and the note panel stayed dark**, because a window with no preference of
            // its own follows the system. A setting that works in some of an app's windows is
            // worse than one that works in none: it reads as a bug in the theme rather than a
            // gap in the plumbing. Found by looking at the light-mode screenshots, which is
            // the only way it could have been found — every check in the suite passed.
            .preferredColorScheme(forcing ?? preferences.appearance.colorScheme)
    }
}

/// The app's own icon, resolved from the bundle rather than asked of `NSApplication`.
///
/// Named for the bundle rather than the app because `AppIcon` is already taken by the view
/// that draws *other* applications' icons.
///
/// `NSApp.applicationIconImage` goes through Launch Services, which caches by bundle path —
/// so a bundle that has just been rewritten in place (which `scripts/make-app.sh` does on
/// every build) can hand back the generic document icon instead. That is the "sometimes" in
/// "the icon is sometimes missing": nothing is wrong with the icon, the lookup is answering
/// from a stale cache.
///
/// Reading the `.icns` out of the bundle skips that entirely. `NSApp`'s copy is still the
/// fallback, because it is right whenever Launch Services is.
@MainActor
enum BundleIcon {
    static let image: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let fromBundle = NSImage(contentsOf: url) {
            return fromBundle
        }
        return NSApp.applicationIconImage
    }()
}

/// A light travelling once around a rounded border, for as long as something is happening.
///
/// Not a package. `border-beam` ships a SwiftUI one and CLAUDE.md forbids external
/// dependencies — a rule worth more than the thirty lines it saves, and the effect is thirty
/// lines: an angular gradient turning behind a stroked rounded rectangle, which masks it to
/// the border.
///
/// **Off entirely under Reduce Motion**, rather than slowed. Somebody who has asked the system
/// to stop moving things has not asked for a slower moving thing, and the state it reports is
/// already written in words beside it.
struct BorderBeam: ViewModifier {
    let active: Bool
    var radius: CGFloat = Design.Radius.card

    @Environment(\.motion) private var motion

    func body(content: Content) -> some View {
        content.overlay {
            if active && !motion.reduced {
                // `SwiftUI.` because this app has a `TimelineView` of its own — the
                // Timeline surface — and the unqualified name resolves to that one.
                SwiftUI.TimelineView(.animation) { timeline in
                    let turn = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: Design.Beam.seconds) / Design.Beam.seconds
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            AngularGradient(
                                stops: [
                                    .init(color: .accentColor.opacity(Design.Beam.floor), location: 0),
                                    .init(color: .accentColor, location: Design.Beam.arc / 2),
                                    .init(color: .accentColor.opacity(Design.Beam.floor), location: Design.Beam.arc),
                                    .init(color: .accentColor.opacity(Design.Beam.floor), location: 1),
                                ],
                                center: .center,
                                angle: .degrees(turn * 360)
                            ),
                            lineWidth: Design.Beam.width
                        )
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
    }
}

extension View {
    /// A travelling border while `active`. See ``BorderBeam`` for why there is one use of it.
    func borderBeam(_ active: Bool, radius: CGFloat = Design.Radius.card) -> some View {
        modifier(BorderBeam(active: active, radius: radius))
    }
}


extension Color {
    /// The same hue, with saturation and brightness raised to a floor.
    ///
    /// `Color` cannot be inspected directly, so this goes through `NSColor` and back. The
    /// conversion needs a known colour space: an `NSColor` built from a SwiftUI `Color` can be
    /// in a space with no `saturationComponent` at all, and asking for one raises rather than
    /// returning something wrong. `deviceRGB` is the safe landing place, and failure falls
    /// back to the original colour rather than to an assertion.
    func lifted(minimumSaturation: Double, minimumBrightness: Double) -> Color {
        guard let rgb = NSColor(self).usingColorSpace(.deviceRGB) else { return self }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(
            hue: hue,
            saturation: max(saturation, minimumSaturation),
            brightness: max(brightness, minimumBrightness),
            opacity: alpha
        )
    }
}
