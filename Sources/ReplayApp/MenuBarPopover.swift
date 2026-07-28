import AppKit
import ReplayCore
import SwiftUI

/// The menu bar item, opened.
///
/// The menu it replaces answered two questions well — what am I in, and what was I just in —
/// and could not answer any more than that, because a menu is rows of text. This shows the
/// same two answers plus the three a person actually pulls the menu bar down for: how the day
/// is going, how the goal is going, and a way to stop recording without hunting for it.
///
/// **Read mid-task, which decides everything about it.** Every figure is on one screen with no
/// scrolling; nothing here is a control you have to aim at; and it closes the moment you look
/// away. It is deliberately not a small copy of Today — the window is one keystroke behind the
/// first button, and a second Today that lagged the first would be worse than no Today at all.
///
/// The reference has no menu bar (it runs inside the Glaze shell), so this whole surface is
/// this port's own. The decisions are in `MenuBar.Popover` where the tests can reach them.
struct MenuBarPopoverView: View {
    let model: AppModel
    let preferences: Preferences

    var onOpenToday: () -> Void
    var onOpenTimeline: () -> Void
    var onToggleTracking: () -> Void
    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    /// Ticks the "focused for" line without asking the tracker for anything.
    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                nowBlock
                today.padding(.top, Design.Space.section)
                if !recent.isEmpty { recentBlock.padding(.top, Design.Space.section) }
            }
            .padding(.horizontal, Design.Space.cardRoomy)

            // Rows run edge to edge, so their highlight is a band across the panel rather
            // than a floating pill. That is what makes a list read as a menu.
            Divider().padding(.top, Design.Space.section)
            actions.padding(.top, Design.Space.tight)
        }
        .padding(.top, Design.Space.cardRoomy)
        .padding(.bottom, Design.Space.snug)
        .frame(width: Design.Layout.menuBarPopoverWidth)
        // The panel draws its own material, and it has to.
        //
        // An `NSPopover` hosting a SwiftUI view does not give the content a background — so
        // over a busy desktop the wallpaper showed through the rows *unblurred*, and "Quit
        // Replay" sat on top of somebody's album art. A menu is opaque enough to read against
        // anything, and this is a menu.
        .background(.regularMaterial)
        .onReceive(clock) { now = $0 }
    }

    // MARK: - What is happening right now

    private var state: MenuBar.Now {
        MenuBar.now(
            isRecording: model.isRecording, isAway: model.isAway,
            current: model.current, now: Int64(now.timeIntervalSince1970 * 1000)
        )
    }

    @ViewBuilder
    private var nowBlock: some View {
        switch state {
        case .inApplication(let name, let seconds):
            HStack(spacing: Design.Space.card) {
                AppIcon(
                    bundleID: model.currentApp?.bundleID, appPath: model.currentApp?.appPath,
                    size: Design.Icon.feature
                )
                VStack(alignment: .leading, spacing: Design.Space.hairline) {
                    Text(name).font(Design.Text.itemTitle)
                    Text(MenuBar.focusedFor(seconds))
                        .font(Design.Text.detail)
                        .foregroundStyle(.secondary)
                        // The seconds tick; without this the row jitters as the width changes.
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
        case .paused, .away, .waiting:
            HStack(spacing: Design.Space.inline) {
                Image(systemName: quietGlyph)
                    .font(Design.Text.itemTitle)
                    .foregroundStyle(.secondary)
                    .frame(width: Design.Icon.sidebarColumn)
                Text(quietLabel).font(Design.Text.itemTitle).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }

    private var quietGlyph: String {
        switch state {
        case .paused: "pause.circle"
        case .away: "moon.zzz"
        default: "hourglass"
        }
    }

    private var quietLabel: String {
        switch state {
        case .paused: MenuBar.pausedLabel
        case .away: MenuBar.awayLabel
        default: MenuBar.waitingLabel
        }
    }

    // MARK: - The day, and the goal

    private var today: some View {
        VStack(alignment: .leading, spacing: Design.Space.snug) {
            Text(MenuBar.Popover.todayHeading).cardLabelStyle()
            Text(
                MenuBar.Popover.todayLine(
                    activeSeconds: model.summary?.activeSeconds ?? 0,
                    sessions: model.sessions.count
                )
            )
            .font(Design.Text.figure)
            .monospacedDigit()

            if let goal = preferences.focusGoalMinutes {
                goalBar(goal)
            }
        }
    }

    /// A bar rather than the ring Today uses.
    ///
    /// The ring is right on a card it has room to anchor; at this width it would be a small
    /// circle of thin stroke read at a glance, which is the one job a ring is bad at. A bar
    /// says "how far along" in a shape the eye reads without focusing.
    private func goalBar(_ goalMinutes: Int) -> some View {
        let progress = Goals.progress(
            activeSeconds: model.summary?.activeSeconds ?? 0, goalMinutes: goalMinutes
        )
        return VStack(alignment: .leading, spacing: Design.Space.tight) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Design.Colour.fill)
                    Capsule()
                        .fill(progress.met ? AnyShapeStyle(Design.Colour.met) : AnyShapeStyle(.tint))
                        .frame(width: max(0, geometry.size.width * progress.fraction))
                }
            }
            .frame(height: Design.Layout.menuBarGoalBar)
            Text(
                MenuBar.Popover.goalLine(
                    activeSeconds: model.summary?.activeSeconds ?? 0, goalMinutes: goalMinutes
                )
            )
            .font(Design.Text.detail)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - What you were just in

    private var recent: [ActivitySession] {
        MenuBar.Popover.sessions(in: model.sessions)
    }

    private var recentBlock: some View {
        VStack(alignment: .leading, spacing: Design.Space.snug) {
            Text(MenuBar.Popover.recentHeading).cardLabelStyle()
            ForEach(recent, id: \.startedAt) { session in
                HStack(spacing: Design.Space.inline) {
                    HStack(spacing: Design.Space.hairline) {
                        ForEach(session.apps.prefix(3), id: \.applicationName) { app in
                            AppIcon(
                                bundleID: app.bundleIdentifier, appPath: app.appPath,
                                size: Design.Icon.inline
                            )
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(session.title)
                            .font(Design.Text.detail)
                            .lineLimit(1)
                        Text(formatRange(session.startedAt, session.endedAt))
                            .font(Design.Text.micro)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Design.Space.tight)
                    Text(formatDurationShort(session.activeSeconds))
                        .font(Design.Text.micro)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - The controls

    /// Rows rather than buttons, and it took seeing the first version to know why.
    ///
    /// Buttons gave five controls five different weights — a saturated blue pill, two
    /// bordered capsules of different widths, and two icon squares floated to the right —
    /// in a panel 300 points wide. The eye went to the blue first, which is exactly
    /// backwards: the figures are the content and the actions are the exits. A list of
    /// equal, quiet rows that highlight under the pointer is what every menu bar app does,
    /// and it is calmer to read *and* easier to hit, since the target is the whole width.
    private var actions: some View {
        VStack(spacing: 0) {
            // Its own group, because it is the only thing here that changes what Replay does
            // rather than where you are.
            MenuBarRow(
                glyph: model.isRecording ? "pause.circle" : "play.circle",
                title: MenuBar.Popover.trackingLabel(isRecording: model.isRecording),
                action: onToggleTracking
            )
            rowDivider
            MenuBarRow(glyph: "square.grid.2x2", title: "Open Replay", shortcut: "⌘1", action: onOpenToday)
            MenuBarRow(glyph: "calendar.day.timeline.left", title: "Timeline", shortcut: "⌘4", action: onOpenTimeline)
            rowDivider
            MenuBarRow(glyph: "gearshape", title: "Settings…", shortcut: "⌘,", action: onOpenSettings)
            MenuBarRow(glyph: "power", title: "Quit Replay", shortcut: "⌘Q", action: onQuit)
        }
        // Without this the first row takes focus as the panel opens and wears a focus ring,
        // which reads as "armed, press Return" on something whose first item pauses
        // recording. A menu does not open with an item selected, and neither should this.
        .focusEffectDisabled()
    }

    private var rowDivider: some View {
        Divider()
            .padding(.horizontal, Design.Space.cardRoomy)
            .padding(.vertical, Design.Space.tight)
    }
}

/// One line of the popover's menu: a glyph, a label, and the shortcut that does the same
/// thing from the keyboard.
///
/// The shortcut is shown because this panel is the discoverable route to things the window
/// already does faster — somebody who opens the menu bar twice a day to hit "Timeline" should
/// be told there is a ⌘4, not left clicking.
private struct MenuBarRow: View {
    let glyph: String
    let title: String
    var shortcut: String?
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.motion) private var motion

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Space.inline) {
                Image(systemName: glyph)
                    .font(Design.Text.detail)
                    // A fixed column, because SF Symbols are not one width and ragged labels
                    // are the first thing that makes a list look unmade.
                    .frame(width: Design.Icon.sidebarColumn)
                    .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                Text(title).font(Design.Text.itemTitle)
                Spacer(minLength: Design.Space.inline)
                if let shortcut {
                    Text(shortcut)
                        .font(Design.Text.micro)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, Design.Space.cardRoomy)
            .padding(.vertical, Design.Space.snug)
            // Before the background, so the whole band is the target rather than the text.
            .contentShape(Rectangle())
            .background {
                if hovering {
                    Rectangle().fill(Design.Colour.fill)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(motion.animation(Design.Motion.inPlace)) { hovering = inside }
        }
    }
}
