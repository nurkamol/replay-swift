import ReplayCore
import SwiftUI

/// A slow drift through the day.
///
/// Today's sessions rising past a memory and the applications you reach for most. Muted and
/// unhurried: no bright colours, nothing that asks for attention, nothing that counts down.
/// The icons are desaturated because the point is the shape of a day rather than a parade of
/// logos.
///
/// The column is drawn twice and the whole thing translates by exactly one copy's height, so
/// the loop closes on itself with no seam.
struct ScreensaverView: View {
    let model: AppModel
    let memories: MemoriesModel
    let preferences: Preferences
    let onExit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false
    @State private var height: CGFloat = 0
    /// Loaded once, before the first layout.
    ///
    /// This was `@State` set in `onAppear` at first, and the loop came apart: the column was
    /// measured without the favourites, they arrived, the column got taller, and the drift
    /// kept travelling the old distance — so the second copy rode up into the first. The
    /// data a layout depends on has to exist before that layout happens.
    private let favourites: [AppStat]

    init(
        model: AppModel, memories: MemoriesModel, preferences: Preferences,
        onExit: @escaping () -> Void
    ) {
        self.model = model
        self.memories = memories
        self.preferences = preferences
        self.onExit = onExit
        // Reads the store; does not touch any observable model. Loading `memories` here
        // would be mutating state while a view is being built, which is the parent's job —
        // the window opener does it before this view exists.
        favourites = Self.favourites(model: model, preferences: preferences)
    }

    private var sessions: [ActivitySession] {
        model.timeline.compactMap {
            if case .session(let session) = $0 { return session } else { return nil }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Design.Colour.screensaverBackground.ignoresSafeArea()

            // No `GeometryReader` around this. One was wrapped here first and the layout
            // fell apart: a `GeometryReader` proposes its own full height to its child, so
            // the two columns were squeezed into one screen and their titles overlapped the
            // icons beneath them. `fixedSize` vertically is what makes the stack take the
            // height it actually wants, which is also the height the drift has to travel.
            VStack(spacing: 0) {
                column
                column
            }
            .frame(width: Design.Layout.screensaverColumnWidth)
            .fixedSize(horizontal: false, vertical: true)
            // Measured rather than assumed, and tracked rather than sampled once: the drift
            // has to be exactly one copy's height or the loop shows its seam.
            .onGeometryChange(for: CGFloat.self) { $0.size.height / 2 } action: { measured in
                if abs(measured - height) > 0.5 { height = measured }
            }
            .offset(y: drift ? -height : 0)
            .animation(
                .linear(duration: reduceMotion
                    ? Design.Motion.screensaverSlowSeconds
                    : Design.Motion.screensaverDriftSeconds)
                    .repeatForever(autoreverses: false),
                value: drift
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()

            // Content dissolves at the edges rather than clipping.
            VStack {
                fade(.top)
                Spacer()
                fade(.bottom)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            HStack {
                Spacer()
                Button(action: onExit) {
                    Image(systemName: "xmark")
                        .font(Design.Text.detail)
                        .padding(Design.Space.row)
                }
                .buttonStyle(.plain)
                .background(.thinMaterial, in: Circle())
                .opacity(Design.Colour.screensaverExitOpacity)
                .padding(Design.Space.page)
                .keyboardShortcut(.escape, modifiers: [])
                .help("Exit")
                .accessibilityLabel("Exit the screensaver")
            }

            VStack {
                Spacer()
                Text("Press Esc to exit")
                    .font(Design.Text.micro)
                    .foregroundStyle(.white.opacity(Design.Colour.screensaverHintOpacity))
                    .padding(.bottom, Design.Space.page)
            }
        }
        // Started only once there is a distance to travel, so the animation is never given
        // a target of zero and then re-targeted mid-flight.
        .onChange(of: height, initial: true) { _, measured in
            if measured > 0 && !drift { drift = true }
        }
    }

    private func fade(_ edge: VerticalEdge) -> some View {
        LinearGradient(
            colors: [Design.Colour.screensaverBackground, .clear],
            startPoint: edge == .top ? .top : .bottom,
            endPoint: edge == .top ? .bottom : .top
        )
        .frame(height: Design.Layout.screensaverFade)
    }

    private var column: some View {
        VStack(spacing: Design.Space.screensaverGap) {
            if let memory = memories.memories.first {
                VStack(spacing: Design.Space.tight) {
                    caption("On this day")
                    Text(memory.range.label)
                        .font(Design.Text.screensaverHeading)
                        .foregroundStyle(.white.opacity(Design.Colour.screensaverPrimary))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(
                        "\(memoryDateLabel(memory.range.dayStart)) · "
                            + "\(formatDurationShort(memory.summary.activeSeconds)) active"
                    )
                    .font(Design.Text.body)
                    .foregroundStyle(.white.opacity(Design.Colour.screensaverTertiary))
                }
            }

            ForEach(sessions, id: \.startedAt) { session in
                VStack(spacing: Design.Space.snug) {
                    HStack(spacing: Design.Space.snug) {
                        ForEach(session.apps.prefix(5), id: \.applicationName) { app in
                            AppIcon(
                                bundleID: app.bundleIdentifier,
                                appPath: app.appPath,
                                size: Design.Icon.screensaverStack
                            )
                            .grayscale(1)
                        }
                    }
                    .opacity(Design.Colour.screensaverIconOpacity)
                    Text(session.title)
                        .font(Design.Text.screensaverTitle)
                        .foregroundStyle(.white.opacity(Design.Colour.screensaverSecondary))
                        .multilineTextAlignment(.center)
                        // Wraps rather than truncating: a session's name is the line worth
                        // reading, and "Late night in Termi…" is worse than two lines.
                        .fixedSize(horizontal: false, vertical: true)
                    Text(
                        "\(formatRange(session.startedAt, session.endedAt)) · "
                            + formatDurationShort(session.activeSeconds)
                    )
                    .font(Design.Text.detail)
                    .foregroundStyle(.white.opacity(Design.Colour.screensaverQuiet))
                    .monospacedDigit()
                }
            }

            if !favourites.isEmpty {
                VStack(spacing: Design.Space.card) {
                    caption("Favourite apps")
                    HStack(spacing: Design.Space.card) {
                        ForEach(favourites, id: \.key) { app in
                            AppIcon(
                                bundleID: app.bundleIdentifier,
                                appPath: app.appPath,
                                size: Design.Icon.screensaverFavourite
                            )
                            .grayscale(1)
                        }
                    }
                    .opacity(Design.Colour.screensaverFavouriteOpacity)
                }
                .padding(.top, Design.Space.section)
            }
        }
        .padding(.vertical, Design.Space.screensaverPadding)
        .padding(.horizontal, Design.Space.page)
        .frame(maxWidth: .infinity)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Design.Text.cardLabel)
            .kerning(Design.Text.screensaverKerning)
            .textCase(.uppercase)
            .foregroundStyle(.white.opacity(Design.Colour.screensaverQuiet))
    }

    /// The applications to show: the ones pinned on Apps if any have been, else the busiest
    /// of the week. Pinning is a statement about what matters, so it wins where it exists.
    private static func favourites(model: AppModel, preferences: Preferences) -> [AppStat] {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let from = startOfLocalDay(now) - 6 * dayMillis
        let events = ((try? model.store.sessions(from: from, to: now + dayMillis)) ?? [])
            .filter { $0.startedAt >= from }
        let stats = computeAppStats(excludeIdleStretches(events, now: now), now: now)
        if !preferences.pinnedApps.isEmpty {
            let byID = Dictionary(
                stats.compactMap { stat in stat.bundleIdentifier.map { ($0, stat) } },
                uniquingKeysWith: { first, _ in first }
            )
            let picked = preferences.pinnedApps.compactMap { byID[$0] }
            if !picked.isEmpty { return Array(picked.prefix(6)) }
        }
        return Array(stats.prefix(6))
    }
}
