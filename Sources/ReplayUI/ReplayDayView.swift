import ReplayCore
import SwiftUI

/// A day, played back.
///
/// One moment fills the screen and gives way to the next as the playhead sweeps the day, with
/// a filmstrip along the bottom to see where you are and to scrub. It is meant to feel like
/// watching a memory rather than reading a dashboard, which is why there are no figures on
/// screen beyond the ones that belong to the moment itself.
///
/// The clock is the day's own span mapped onto half a minute, so the gaps are still felt: a
/// morning with nothing in it passes as a pause rather than as a cut.
struct ReplayDayView: View {
    let sessions: [ActivitySession]
    let label: String
    let onClose: () -> Void

    @Environment(\.motion) private var motion
    @State private var progress: Double = 0
    @State private var playing = true
    @State private var speed = 1
    @State private var lastTick: Date?
    /// Whether the day is being dragged, and whether the pointer is merely over the strip.
    /// Two states, not one: hovering says "this is a control", scrubbing says "you have it".
    @State private var scrubbing = false
    @State private var hoveringStrip = false

    private var current: ActivitySession? {
        Playback.session(at: progress, in: sessions)
    }

    var body: some View {
        ZStack {
            // The hour the playhead is on, so watching a day back passes through its own
            // light — late night, dawn, the middle of the afternoon, evening.
            Sky(at: Playback.time(at: progress, in: sessions))
                .ignoresSafeArea()

            if let current {
                moment(current)
                    // Re-keyed on the session, so each one arrives rather than the text
                    // changing underneath a frame that never moved.
                    .id(current.startedAt)
                    .transition(motion.transition(
                        .opacity.combined(with: .scale(scale: 0.98))
                    ))
            }

            VStack {
                HStack {
                    Spacer()
                    // The hit area is the whole disc, not the glyph inside it. The first
                    // version put the material *behind* a plain button, so only the ✕ itself
                    // was clickable — a 12-point target that looked like a 34-point one, and
                    // in practice only Escape worked.
                    Button(action: onClose) {
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
                    .keyboardShortcut(.escape, modifiers: [])
                    .help(Loc.t("Close"))
                    .accessibilityLabel(Loc.t("Close"))
                }
                Spacer()
                transport
            }
            .padding(Design.Space.page)
        }
        .animation(motion.animation(Design.Motion.settle), value: current?.startedAt)
        // A clock rather than a repeating animation: the playhead has to be readable at any
        // instant — for the filmstrip, for the scrubber, for which moment is on screen — and
        // an animated value is only readable by the thing being animated.
        .onReceive(
            Timer.publish(every: Design.Motion.playbackTick, on: .main, in: .common).autoconnect()
        ) { now in
            guard playing else {
                lastTick = now
                return
            }
            let elapsed = now.timeIntervalSince(lastTick ?? now)
            lastTick = now
            let step = elapsed * 1000 * Double(speed) / Double(Playback.baseDurationMillis)
            progress = min(1, progress + step)
            if progress >= 1 { playing = false }
        }
    }

    private func moment(_ session: ActivitySession) -> some View {
        VStack(spacing: Design.Space.block) {
            AppIcon(
                bundleID: session.apps.first?.bundleIdentifier,
                appPath: session.apps.first?.appPath,
                size: Design.Icon.playbackMark
            )
            VStack(spacing: Design.Space.snug) {
                Text(String(
                    format: Loc.t("%1$@ · %2$@"),
                    dayPart(of: session.startedAt), session.category.rawValue
                ))
                    .cardLabelStyle()
                Text(session.localizedTitle)
                    .font(Design.Text.playbackTitle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    "\(formatRange(session.startedAt, session.endedAt)) · "
                        + formatDurationShort(session.activeSeconds)
                )
                .font(Design.Text.body)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            HStack(spacing: Design.Space.snug) {
                ForEach(session.apps.prefix(6), id: \.applicationName) { app in
                    AppIcon(
                        bundleID: app.bundleIdentifier, appPath: app.appPath,
                        size: Design.Icon.stack
                    )
                }
            }
        }
        .frame(maxWidth: Design.Layout.readableWidth)
        .accessibilityElement(children: .combine)
    }

    private var transport: some View {
        VStack(spacing: Design.Space.card) {
            filmstrip
            HStack(spacing: Design.Space.card) {
                Button {
                    if progress >= 1 { progress = 0 }
                    playing.toggle()
                    lastTick = Date()
                } label: {
                    Image(systemName: progress >= 1 ? "arrow.counterclockwise" : (playing ? "pause.fill" : "play.fill"))
                        .font(Design.Text.itemTitle)
                        .frame(width: Design.Icon.listItem)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])
                .help(playing ? "Pause" : "Play")

                Text(clock)
                    .font(Design.Text.detail)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Spacer(minLength: Design.Space.inline)

                Picker(Loc.t("Speed"), selection: $speed) {
                    ForEach(Playback.speeds, id: \.self) { Text(String(format: Loc.t("%@×"), "\($0)")).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: Design.Layout.playbackSpeedWidth)

                Text(label)
                    .font(Design.Text.detail)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(Design.Space.section)
        .background(.thinMaterial, in: RoundedRectangle(
            cornerRadius: Design.Radius.surface, style: .continuous
        ))
        .frame(maxWidth: Design.Layout.readableWidth)
    }

    /// Where each session sits along the day, and where the playhead is among them.
    private var filmstrip: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(hoveringStrip || scrubbing
                          ? Design.Colour.fillStrong : Design.Colour.fill)
                    .frame(height: Design.Layout.barThickness)
                    .animation(motion.animation(Design.Motion.inPlace), value: hoveringStrip)
                // A mark per session, at its real place in the day — which is what makes the
                // empty stretches visible as empty.
                ForEach(sessions, id: \.startedAt) { session in
                    Capsule()
                        .fill(session.startedAt == current?.startedAt
                              ? AnyShapeStyle(.tint)
                              : Design.Colour.fillStrong)
                        .frame(
                            width: Design.Layout.filmstripMark,
                            height: Design.Layout.barThickness
                        )
                        .offset(x: Playback.offset(of: session, in: sessions) * geometry.size.width)
                }
                Circle()
                    .fill(.white)
                    .frame(width: Design.Layout.playhead, height: Design.Layout.playhead)
                    // Grows on pointer-down, shrinks on release. The scrubber used to answer
                    // a drag only by moving, which says where the day is but not that you
                    // have hold of it.
                    .scaleEffect(scrubbing ? Design.Layout.playheadGrabScale : 1)
                    .animation(motion.animation(Design.Motion.press), value: scrubbing)
                    .offset(x: progress * geometry.size.width - Design.Layout.playhead / 2)
            }
            .frame(height: geometry.size.height, alignment: .center)
            // The band, not the bar. A 12-point target is a 12-point target to the eye and
            // a coin-toss to the pointer; this leaves the drawing alone and makes the
            // grabbable area the height a hand can actually find.
            .frame(height: Design.Layout.barHitRow)
            .contentShape(Rectangle())
            .onHover { hoveringStrip = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        playing = false
                        scrubbing = true
                        progress = min(1, max(0, value.location.x / geometry.size.width))
                    }
                    .onEnded { _ in scrubbing = false }
            )
        }
        .frame(height: Design.Layout.barHitRow)
        .accessibilityLabel(Loc.t("Scrub the day"))
        .accessibilityValue("\(Int(progress * 100)) percent")
    }

    private var clock: String {
        let at = Playback.time(at: progress, in: sessions)
        return Date(timeIntervalSince1970: Double(at) / 1000)
            .formatted(.dateTime.hour().minute().locale(Loc.locale))
    }
}
