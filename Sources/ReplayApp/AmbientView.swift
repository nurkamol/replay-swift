import ReplayCore
import SwiftUI

/// Ambient mode — today, at a distance.
///
/// The other of the reference's two display modes, and the opposite of the screensaver: the
/// screensaver is for when you have gone, this is for while you are here. It is meant for a
/// second monitor across a room — today's active time in type large enough to read from a
/// desk away, the application in front of you right now, and the session you are in.
///
/// **Nothing moves that does not need to.** One number that changes every minute, one icon
/// that changes when you switch, and a single slow breath on that icon so a screen showing a
/// live figure does not read as a screenshot of one. No drift, no parade, no progress. A
/// glanceable surface that asks to be ignored most of the time is doing its job.
struct AmbientView: View {
    let model: AppModel
    let preferences: Preferences
    let onExit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var now = Date()
    @State private var exitMonitor: Any?
    /// The last application seen in front, held across going idle.
    ///
    /// `tracker.current` is nil while away or paused, and *ambient mode is the one surface
    /// where being away is the normal state* — it is a screen you look at without touching
    /// the keyboard, so the away threshold trips while you are sitting there reading it.
    /// Without this the row vanished the moment you stopped typing and came back when you
    /// moved the mouse, and the centred stack reflowed each way. Holding the last one is
    /// also just truer: the application in front has not changed, only your hands have.
    @State private var lastApp: (name: String, bundleID: String?, appPath: String?)?

    /// The application in front right now, and enough about it to draw its icon.
    ///
    /// The tracker knows the name and when it came forward; it does not carry a bundle
    /// identifier or a path, and the icon needs one. So the name is looked up against the
    /// apps of the day's own sessions, newest first — which is where it will be, because
    /// being frontmost is what put it there. No match means no icon rather than no row: the
    /// name is the information and the icon is the ornament.
    private var currentApp: (name: String, bundleID: String?, appPath: String?)? {
        guard let current = model.current else { return lastApp }
        for item in model.timeline.reversed() {
            guard case .session(let session) = item else { continue }
            if let app = session.apps.first(where: { $0.applicationName == current.applicationName }) {
                return (current.applicationName, app.bundleIdentifier, app.appPath)
            }
        }
        return (current.applicationName, nil, nil)
    }

    /// The session being lived in, which is the last one the timeline built.
    private var currentSession: ActivitySession? {
        model.timeline.compactMap {
            if case .session(let session) = $0 { return session } else { return nil }
        }.last
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Design.Colour.screensaverBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // The time first, then the date, then the day's total. The order is the
                    // order the questions come in: what time is it, what day is it, how has
                    // it gone. It sat at the foot of the screen next to the exit hint, which
                    // is where a footnote goes and not where a clock does.
                    if preferences.ambientClock {
                        Text(now.formatted(.dateTime.hour().minute()))
                            .font(.system(size: Design.Layout.ambientClock, weight: .light))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(Design.Colour.ambientHeadline))
                            .padding(.bottom, Design.Space.card)
                    }
                    eyebrow
                    headline(in: geometry.size.width)
                        .padding(.top, Design.Space.block)
                    if preferences.ambientCurrentApp, let app = currentApp {
                        nowPlaying(app).padding(.top, Design.Layout.ambientGap)
                    }
                    if preferences.ambientCurrentSession, let session = currentSession {
                        Text(
                            "\(session.title) · since "
                                + shortTimeLabel(session.startedAt)
                        )
                        .font(Design.Text.body)
                        .foregroundStyle(.white.opacity(Design.Colour.ambientLabel))
                        .padding(.top, Design.Space.block)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .multilineTextAlignment(.center)

                VStack {
                    // Same fix as Replay Day and the screensaver: the hit area is the whole
                    // disc, not the glyph inside it.
                    HStack {
                        Spacer()
                        Button(action: onExit) {
                            Image(systemName: "xmark")
                                .font(Design.Text.detail)
                                .foregroundStyle(.white)
                                .frame(
                                    width: Design.Layout.closeButton,
                                    height: Design.Layout.closeButton
                                )
                                .background(.ultraThinMaterial, in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        // The only focusable thing on the screen, so it takes the focus ring
                        // by default — a blue halo in the corner of a surface whose whole
                        // point is that nothing on it asks for attention. Escape still
                        // leaves, and the disc is still clickable.
                        .focusEffectDisabled()
                        .opacity(Design.Colour.screensaverTertiary)
                        .help("Exit ambient mode")
                        .accessibilityLabel("Exit ambient mode")
                    }
                    Spacer()
                    exitHint
                }
                .padding(Design.Space.page)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Escape leaves, wherever focus happens to be — a borderless window at this
            // level has no title bar and no other way out but the disc.
            exitMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53 else { return event }
                onExit()
                return nil
            }
        }
        .onDisappear {
            if let exitMonitor { NSEvent.removeMonitor(exitMonitor) }
            exitMonitor = nil
        }
        // A minute is the resolution of everything on this screen — the clock shows minutes
        // and the total is formatted in minutes — so anything faster would be redrawing to
        // show the same characters.
        .onReceive(
            Timer.publish(every: Design.Motion.ambientTick, on: .main, in: .common).autoconnect()
        ) { tick in
            now = tick
            model.reload()
            if let seen = currentApp { lastApp = seen }
        }
        .onChange(of: model.current?.applicationName, initial: true) { _, _ in
            if let seen = currentApp { lastApp = seen }
        }
    }

    private var eyebrow: some View {
        Text("Today · \(fullDayLabel(startOfLocalDay(Int64(now.timeIntervalSince1970 * 1000))))")
            .font(Design.Text.detailStrong)
            .textCase(.uppercase)
            .kerning(Design.Layout.ambientEyebrowKerning)
            .foregroundStyle(.white.opacity(Design.Colour.ambientLabel))
    }

    /// Today's total, scaled to the screen it is on.
    ///
    /// Clamped between 72 and 180 points at a sixth of the width, which is the reference's
    /// own rule: a fixed size that reads well on a laptop is lost on a 32-inch display, and
    /// this surface exists for the second display.
    private func headline(in width: CGFloat) -> some View {
        let size = min(
            Design.Layout.ambientHeadlineMax,
            max(Design.Layout.ambientHeadlineMin, width * Design.Layout.ambientHeadlineShare)
        )
        return VStack(spacing: Design.Space.tight) {
            Text(formatDurationShort(model.summary?.activeSeconds ?? 0))
                .font(.system(size: size, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(
                    reduceMotion ? nil : Design.Motion.settle,
                    value: model.summary?.activeSeconds ?? 0
                )
            Text("active today")
                .font(Design.Text.itemTitle)
                .foregroundStyle(.white.opacity(Design.Colour.ambientHeadline))
        }
    }

    private func nowPlaying(
        _ app: (name: String, bundleID: String?, appPath: String?)
    ) -> some View {
        HStack(spacing: Design.Space.section) {
            AppIcon(
                bundleID: app.bundleID,
                appPath: app.appPath,
                size: Design.Layout.ambientIcon
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: Design.Layout.ambientIcon * Design.Radius.iconSquircleRatio,
                    style: .continuous
                )
                .strokeBorder(.white.opacity(Design.Colour.ambientIconRing))
            )
            // The one breath on this screen.
            //
            // A `phaseAnimator` rather than a `repeatForever` implicit animation. The
            // repeating version leaves a transaction live on this subtree for as long as
            // the screen is open, so *any* other change here — a row appearing, the
            // headline's width changing by a digit — gets animated by it too, and a
            // reflow that should be instant slides. `phaseAnimator` owns its own loop and
            // animates nothing but the phase.
            //
            // Anchored explicitly at the centre. It is the default, and stating it is
            // cheap next to the class of bug where an icon swells out of one corner.
            .modifier(Breathing(active: !reduceMotion))

            VStack(alignment: .leading, spacing: Design.Space.hairline) {
                Text("Now")
                    .font(Design.Text.micro)
                    .textCase(.uppercase)
                    .kerning(Design.Layout.ambientNowKerning)
                    .foregroundStyle(.white.opacity(Design.Colour.ambientEyebrow))
                Text(app.name)
                    .font(.system(size: Design.Layout.ambientNowTitle, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now in \(app.name)")
    }

    /// The way out, and nothing else. The time used to share this line; it has gone to the
    /// top, where a clock belongs, and this is a footnote again.
    private var exitHint: some View {
        Text("Press Esc to exit")
            .font(Design.Text.micro)
            .foregroundStyle(.white.opacity(Design.Colour.ambientHint))
    }

    /// The time a session began, in the locale's own short form.
    private func shortTimeLabel(_ millis: Int64) -> String {
        Date(timeIntervalSince1970: Double(millis) / 1000)
            .formatted(.dateTime.hour().minute())
    }
}

/// One slow swell, forever, and nothing else.
///
/// Its own modifier so the phases are stated once and the reduced-motion branch is a plain
/// `if` rather than a nil animation handed to an animator that would still cycle.
private struct Breathing: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.phaseAnimator([false, true]) { view, swollen in
                view
                    .scaleEffect(
                        swollen ? Design.Motion.ambientBreatheScale : 1, anchor: .center
                    )
                    .opacity(swollen ? 1 : Design.Motion.ambientBreatheFloor)
            } animation: { _ in
                .easeInOut(duration: Design.Motion.ambientBreatheSeconds / 2)
            }
        } else {
            content
        }
    }
}
