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
    @State private var exitMonitor: Any?
    /// Only ticked while the clock is shown, and only once a minute — the screensaver
    /// already redraws a drifting column, and a second timer for a figure that changes
    /// sixty times an hour would be the wrong trade.
    @State private var now = Date()
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

            // The column hangs in an *overlay* of a screen-filling `Color.clear` rather
            // than sitting in the stack beside everything else.
            //
            // That is not a stylistic choice. `fixedSize(vertical:)` makes the doubled
            // column take its true height — thousands of points, which is what the drift
            // needs to know — and a `ZStack` sizes itself to its tallest child. So the whole
            // stack became column-height and was centred in the window, which put every
            // other thing in it far above and below the screen: **the close button and the
            // "Press Esc" hint had never been visible.** Nobody noticed because Escape works
            // and a screensaver is mostly looked at rather than used. Found while adding the
            // clock, which landed in the same nowhere.
            //
            // An overlay is sized by its parent and does not feed its own size back, so the
            // stack is the window again and the chrome lands where it was always written to.
            //
            // Still no `GeometryReader`: one was wrapped here first and squeezed the two
            // columns into a single screen, overlapping their titles with the icons beneath.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) {
                    VStack(spacing: 0) {
                        column
                        column
                    }
                    .frame(width: Design.Layout.screensaverColumnWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    // Measured rather than assumed, and tracked rather than sampled once:
                    // the drift has to be exactly one copy's height or the loop shows its
                    // seam.
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
                }
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
                // Same fix as Replay Day: the disc is the target, not the glyph in it.
                Button(action: onExit) {
                    Image(systemName: "xmark")
                        .font(Design.Text.detail)
                        .frame(
                            width: Design.Layout.closeButton,
                            height: Design.Layout.closeButton
                        )
                        .background(.thinMaterial, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                // The only focusable thing on screen, so it takes the focus ring by
                // default — a blue halo on a surface that is meant to be restful. Escape
                // still leaves and the disc is still clickable.
                .focusEffectDisabled()
                .opacity(Design.Colour.screensaverExitOpacity)
                .padding(Design.Space.page)
                .keyboardShortcut(.escape, modifiers: [])
                .help("Exit")
                .accessibilityLabel("Exit the screensaver")
            }

            // Bottom-left, diagonally opposite the close disc, so the two pieces of
            // chrome balance rather than crowd. A corner and not the centre: the column
            // drifts up the middle of the screen for as long as this is open, and a clock
            // laid over moving content is a clock you read twice. It also sits inside the
            // bottom fade, where there is least to read anyway.
            if preferences.screensaverClock {
                VStack {
                    Spacer()
                    HStack {
                        Text(now.formatted(.dateTime.hour().minute()))
                            .font(.system(size: Design.Layout.screensaverClock, weight: .light))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(Design.Colour.screensaverTertiary))
                        Spacer()
                    }
                    .padding(Design.Space.page)
                }
                .allowsHitTesting(false)
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
        // Whatever the user chose dismisses it, after a moment's grace so the very click or
        // keystroke that started it does not immediately end it. Escape and the close button
        // are wired separately and always work, which is why the hint can promise Escape
        // whatever these are set to.
        .onAppear { armExit() }
        .onReceive(
            Timer.publish(every: Design.Motion.ambientTick, on: .main, in: .common).autoconnect()
        ) { tick in
            if preferences.screensaverClock { now = tick }
        }
        .onDisappear {
            if let exitMonitor { NSEvent.removeMonitor(exitMonitor) }
            exitMonitor = nil
        }
    }

    private func armExit() {
        guard exitMonitor == nil else { return }
        var mask: NSEvent.EventTypeMask = []
        if preferences.screensaverExitOnMouseMove { mask.formUnion([.mouseMoved, .scrollWheel]) }
        if preferences.screensaverExitOnClick { mask.formUnion([.leftMouseDown, .rightMouseDown]) }
        if preferences.screensaverExitOnKey { mask.formUnion(.keyDown) }
        guard !mask.isEmpty else { return }

        let armedAt = Date()
        exitMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            if Date().timeIntervalSince(armedAt) > Design.Motion.screensaverArmSeconds {
                onExit()
            }
            return event
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
