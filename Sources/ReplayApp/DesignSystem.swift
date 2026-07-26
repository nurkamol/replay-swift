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

    /// Named roles rather than sizes. A view asks for "the figure a day leads with", not
    /// for 46pt, so the scale can be retuned in one place.
    enum Text {
        /// The number Today exists to show.
        static let hero = Font.system(size: 46, weight: .bold, design: .rounded)
        /// A page title.
        static let title = Font.system(size: 28, weight: .bold)
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
        static let cardLabel = Font.system(size: 9, weight: .semibold)
        /// Prose meant to be read rather than scanned — a day's story.
        static let prose = Font.system(size: 15)
        /// The About panel's mark.
        static let aboutMark = Font.system(size: 44)
        /// A glyph small enough to sit inside a ring or a pill, where the type scale's
        /// smallest step is still too large.
        static let ringFigure = Font.system(size: 11, weight: .medium)
        static let ringGlyph = Font.system(size: 12, weight: .bold)
        static let pillGlyph = Font.system(size: 8, weight: .bold)
        static let closeGlyph = Font.system(size: 7, weight: .bold)

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
    }

    // ── layout ────────────────────────────────────────────────────────────────

    enum Layout {
        /// The main window's default size.
        static let windowWidth: CGFloat = 680
        static let windowHeight: CGFloat = 760
        /// Settings, which is a fixed-size window as Mac settings are.
        static let settingsWidth: CGFloat = 560
        static let settingsHeight: CGFloat = 460
        /// A sheet that lists things — the exclusion picker.
        static let sheetWidth: CGFloat = 460
        static let sheetHeight: CGFloat = 420

        /// The widest a column of text is allowed to get. Beyond this a line is tiring to
        /// read, however wide the window is.
        static let readableWidth: CGFloat = 760

        /// A settings row's control column, so labels and controls align down the page.
        static let settingsControlGap: CGFloat = 16
        /// The width an app name is given in an app-breakdown row, so bars line up.
        static let appNameColumn: CGFloat = 150
        /// And the duration at its end.
        static let durationColumn: CGFloat = 56

        /// A progress bar's thickness.
        static let barThickness: CGFloat = 4
        /// A rule between sections.
        static let hairline: CGFloat = 1
        /// A progress ring's stroke.
        static let ringThickness: CGFloat = 4
        /// The row a progress bar is laid out in.
        static let barRow: CGFloat = 12
        /// A small numeric field in Settings.
        static let numberField: CGFloat = 60
        /// A tag entry field, sized to a tag rather than to the row.
        static let tagField: CGFloat = 90
    }
}

// ── the tokens, applied ───────────────────────────────────────────────────────

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

    /// A page's scrolling content: one gutter, one rhythm, every surface.
    func pageContent() -> some View {
        self
            .padding(Design.Space.page)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
