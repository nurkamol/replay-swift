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
        /// The smallest readable label; used for counts beside an icon.
        static let micro = Font.caption2
        /// An uppercase section label. Pair with ``Design/Text/labelKerning``.
        static let sectionLabel = Font.caption.weight(.semibold)
        /// The uppercase micro-label inside a card.
        static let cardLabel = Font.caption2.weight(.semibold)
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
        /// Something arriving on screen.
        static var entering: Animation { .timingCurve(easeSoft, duration: enterSeconds) }
        /// A press, which should feel like contact rather than animation.
        static var press: Animation { .timingCurve(easeStandard, duration: pressSeconds) }

        /// A list settles one row every `stagger`, capped so a long list finishes rather
        /// than trickling in for seconds.
        static let staggerSeconds: Double = 0.028
        static let staggerCapSeconds: Double = 0.560

        static func enterDelay(_ index: Int, base: Double = 0) -> Double {
            min(base + Double(index) * staggerSeconds, staggerCapSeconds)
        }

        /// A spring for things that move rather than merely change.
        ///
        /// No bounce. Replay's motion is settling, not springing — a card arriving should
        /// look like it came to rest, and overshoot on a list of someone's day reads as
        /// playfulness the content does not have.
        static let settle = Animation.spring(duration: 0.42, bounce: 0)

        /// How long one pass of the screensaver takes, and how long it takes when someone
        /// has asked the system to reduce motion — slower rather than stopped, because a
        /// screensaver that does not move is a poster.
        static let screensaverDriftSeconds: Double = 90
        static let screensaverSlowSeconds: Double = 240
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

        static let border = AnyShapeStyle(.quaternary.opacity(0.50))
        static let borderQuiet = AnyShapeStyle(.quaternary.opacity(0.40))
        static let divider = AnyShapeStyle(.quaternary.opacity(0.60))

        /// A bookmarked session's warmed border, and its mark.
        static let marked = Color.yellow
        /// How far a bookmarked border is warmed, and a streak's background tinted.
        static let markedOpacity: Double = 0.45
        static let streakOpacity: Double = 0.12

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
        static let canvasProjectOpacity: Double = 0.65
        static let canvasChapterOpacity: Double = 0.70
        static let canvasMomentOpacity: Double = 0.80
        static let canvasAppOpacity: Double = 0.55
        /// A ring around an icon. An application wears a quiet one — its own icon already
        /// says what it is — and everything built on top of one wears a solid ring, so a
        /// project is never mistaken for the app whose icon it borrows.
        static let canvasRingQuiet: Double = 0.35

        /// The screensaver. Everything is white at a chosen weight rather than a palette:
        /// the room it plays in is dark, and colour would be the thing asking for attention.
        static let screensaverBackground = Color(red: 0.027, green: 0.027, blue: 0.035)
        static let screensaverPrimary: Double = 0.80
        static let screensaverSecondary: Double = 0.70
        static let screensaverTertiary: Double = 0.35
        static let screensaverQuiet: Double = 0.30
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

        /// The widest a column of text is allowed to get. Beyond this a line is tiring to
        /// read, however wide the window is.
        static let readableWidth: CGFloat = 760

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
        /// The widest a rhythm strip is allowed to get. Twenty-four bars stretched across
        /// a full-screen window stop being a strip and become a row of blocks; capped, the
        /// shape of a day stays legible at any window size.
        static let arcMaxWidth: CGFloat = 560
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
        static let canvasSymbolSize: CGFloat = 96
        /// A badge on a node that wears another thing's icon, and the glyph inside it.
        static let canvasBadgeRadius: CGFloat = 7
        static let canvasBadgeGlyph: CGFloat = 8
        /// Padding around a label when deciding whether two of them collide.
        static let canvasLabelPadding: CGFloat = 4
        /// The ring that keeps a node's kind legible once its face is an app icon.
        static let canvasRingWidth: CGFloat = 2
        static let canvasRingWidthStrong: CGFloat = 3
        static let canvasHitSlack: CGFloat = 6
        static let canvasMinZoom: CGFloat = 0.4
        static let canvasMaxZoom: CGFloat = 3
        static let canvasPreviewWidth: CGFloat = 300
        /// One press of zoom in or out. A ratio rather than a step, so each press feels the
        /// same however far in you already are.
        static let canvasZoomStep: CGFloat = 1.35
        /// The magnification readout, wide enough for "300%" so the toolbar does not shuffle.
        static let canvasZoomReadoutWidth: CGFloat = 44
        /// Where a double-click lands you: close enough to read a node's neighbourhood.
        static let canvasFocusZoom: CGFloat = 1.8
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
        self
            .background(background, in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                if let border {
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(border, lineWidth: Design.Layout.hairline)
                }
            }
            .shadow(
                color: .black.opacity(elevation.shadowOpacity),
                radius: elevation.shadowRadius,
                y: elevation.shadowOffsetY
            )
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
        scrollTransition(.interactive, axis: .vertical) { content, phase in
            content
                .opacity(reduced ? 1 : (phase.isIdentity ? 1 : 0.6))
                .scaleEffect(reduced ? 1 : (phase.isIdentity ? 1 : 0.985))
        }
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
    func pageContent() -> some View {
        self
            .padding(Design.Space.page)
            .frame(maxWidth: Design.Layout.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
