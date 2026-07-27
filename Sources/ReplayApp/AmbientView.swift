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
    let onExit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var now = Date()
    @State private var breathing = false
    @State private var exitMonitor: Any?

    /// The application in front right now, and enough about it to draw its icon.
    ///
    /// The tracker knows the name and when it came forward; it does not carry a bundle
    /// identifier or a path, and the icon needs one. So the name is looked up against the
    /// apps of the day's own sessions, newest first — which is where it will be, because
    /// being frontmost is what put it there. No match means no icon rather than no row: the
    /// name is the information and the icon is the ornament.
    private var currentApp: (name: String, bundleID: String?, appPath: String?)? {
        guard let current = model.current else { return nil }
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
                    eyebrow
                    headline(in: geometry.size.width)
                        .padding(.top, Design.Space.block)
                    if let app = currentApp {
                        nowPlaying(app).padding(.top, Design.Layout.ambientGap)
                    }
                    if let session = currentSession {
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
                    clock
                }
                .padding(Design.Space.page)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            breathing = true
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
            // The one breath on this screen. Driven off a repeating animation rather than a
            // clock because nothing else here is animating — there is no frame loop to hang
            // it on, and starting one for a six-second swell would be the wrong trade.
            .scaleEffect(breathing && !reduceMotion ? Design.Motion.ambientBreatheScale : 1)
            .opacity(breathing && !reduceMotion ? 1 : Design.Motion.ambientBreatheFloor)
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: Design.Motion.ambientBreatheSeconds / 2)
                        .repeatForever(autoreverses: true),
                value: breathing
            )

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

    private var clock: some View {
        Text("\(now.formatted(.dateTime.hour().minute())) · press Esc to exit")
            .font(Design.Text.micro)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(Design.Colour.ambientHint))
    }

    /// The time a session began, in the locale's own short form.
    private func shortTimeLabel(_ millis: Int64) -> String {
        Date(timeIntervalSince1970: Double(millis) / 1000)
            .formatted(.dateTime.hour().minute())
    }
}
