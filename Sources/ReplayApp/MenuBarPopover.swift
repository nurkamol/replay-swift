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
    var onAddNote: () -> Void
    var onPause: (Pause.Span) -> Void
    var onExcludeCurrent: () -> Void
    var onQuit: () -> Void

    /// Whether the three pause lengths are showing. Not remembered: the panel is rebuilt
    /// every time it opens, and a menu that reopens half-expanded is a menu that remembers
    /// something nobody asked it to.
    @State private var showingPauseSpans = false
    @Environment(\.motion) private var motion

    /// Ticks the "focused for" line without asking the tracker for anything.
    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// The stretch being lived in — the newest session the day has.
    ///
    /// The one a note or a bookmark can be about, because it is the only one this panel is
    /// *about*. Anything older is a row in the window, where there is room to choose which.
    private var currentSession: ActivitySession? {
        model.sessions.max { $0.startedAt < $1.startedAt }
    }

    private var currentAnnotation: SessionAnnotation? {
        currentSession.map { model.annotations.annotation(for: $0.startedAt) }
    }

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
        case .paused:
            // A pause with an end says so. "Tracking paused" and "Paused until 2:30 PM" are
            // different facts, and the second is the one that stops somebody wondering all
            // afternoon whether they left it off.
            if let until = preferences.pausedUntil {
                String(
                    format: Loc.t("Paused until %@"),
                    until.formatted(.dateTime.hour().minute())
                )
            } else {
                MenuBar.pausedLabel
            }
        case .away: MenuBar.awayLabel
        default: MenuBar.waitingLabel
        }
    }

    // MARK: - The day, and the goal

    private var today: some View {
        VStack(alignment: .leading, spacing: Design.Space.snug) {
            Text(Loc.t(MenuBar.Popover.todayHeading)).cardLabelStyle()
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
            Text(Loc.t(MenuBar.Popover.recentHeading)).cardLabelStyle()
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
            // Only while recording, and beside the plain pause rather than replacing it:
            // stopping indefinitely is still a thing people mean, and burying it inside a
            // menu of durations would make the simple case the awkward one.
            if model.isRecording { pauseForRow }
            // "Never record this one" belongs where the application is *named*, which is here
            // and nowhere else in the app — Settings has a picker of every app you have ever
            // used, and finding today's in it is the work this row removes.
            //
            // It asks first, and that is not politeness: excluding also erases everything
            // already recorded for that application, which is the one action in this panel
            // that cannot be undone.
            if let app = model.currentApp, model.isRecording {
                MenuBarRow(
                    glyph: "eye.slash",
                    title: String(format: Loc.t("Never record %@"), app.name),
                    action: onExcludeCurrent
                )
            }
            annotate
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

    /// "Pause for…", and then the three ends, as rows.
    ///
    /// **It was a `Menu`, and it did not look like the panel it was in.** SwiftUI gives a menu
    /// its own chrome — an inset, a background, its own idea of a control's shape — so the row
    /// sat indented inside a rounded box while every other row ran flush edge to edge. In a
    /// list whose whole design is "equal, quiet rows", one row wearing a button was the only
    /// thing the eye went to.
    ///
    /// So it expands in place instead. The three ends are `MenuBarRow`s like everything else,
    /// which makes them identical by construction rather than by matching padding twice, and
    /// the state resets when the panel closes because the panel is rebuilt each time it opens.
    @ViewBuilder
    private var pauseForRow: some View {
        MenuBarRow(
            glyph: showingPauseSpans ? "clock.badge.checkmark" : "clock.badge.xmark",
            title: Loc.t("Pause for…"),
            action: { withAnimation(motion.animation(Design.Motion.inPlace)) { showingPauseSpans.toggle() } }
        )
        if showingPauseSpans {
            ForEach(Pause.Span.allCases, id: \.self) { span in
                MenuBarRow(
                    glyph: "circle.dashed",
                    title: span.label,
                    indented: true,
                    action: { onPause(span) }
                )
            }
        }
    }

    // MARK: - Marking the stretch you are in

    /// A bookmark and a note, on the session in progress, without opening the window.
    ///
    /// The reason this belongs here and not only on a card: the moment worth marking is the
    /// one you are *in*, and it passes. Reaching it meant ⌘1, finding the session, expanding
    /// it, typing — four steps, by which time the thought has gone and the session may have
    /// ended and become two. This is the same two writes the card does, through the same
    /// shared model, so a bookmark set here is already true when Today next draws.
    ///
    /// The bookmark does not close the panel — it is the one thing here you do *to*
    /// something rather than a way out, and being thrown out the instant you mark something
    /// is how you lose track of whether it worked. The note does, because it opens a window
    /// of its own: a text field cannot live in a popover, which does not take the keyboard.
    /// See ``NoteView``.
    @ViewBuilder
    private var annotate: some View {
        if let session = currentSession {
            let annotation = model.annotations.annotation(for: session.startedAt)
            MenuBarRow(
                glyph: annotation.bookmarked ? "bookmark.fill" : "bookmark",
                title: annotation.bookmarked
                    ? Loc.t("Bookmarked")
                    : Loc.t("Bookmark this session"),
                action: {
                    model.annotations.setBookmarked(session.startedAt, !annotation.bookmarked)
                }
            )
            MenuBarRow(
                glyph: "square.and.pencil",
                title: annotation.note.isEmpty ? Loc.t("Add a note…") : Loc.t("Edit the note"),
                action: onAddNote
            )
            if !annotation.note.isEmpty {
                Text(annotation.note)
                    .font(Design.Text.micro)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Design.Space.cardRoomy)
                    .padding(.bottom, Design.Space.snug)
            }
        }
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
    /// A row that belongs to the one above it — the pause lengths under "Pause for…". Indented
    /// by the glyph column rather than by a made-up number, so it lines up with the *titles*
    /// above it and reads as a continuation of the list rather than as a second list.
    var indented = false
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
                    // The row's title says what it does; the glyph repeats it in pictures.
                    .accessibilityHidden(true)
                Text(title).font(Design.Text.itemTitle)
                Spacer(minLength: Design.Space.inline)
                if let shortcut {
                    Text(shortcut)
                        .font(Design.Text.micro)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, Design.Space.cardRoomy + (indented ? Design.Icon.sidebarColumn : 0))
            .padding(.trailing, Design.Space.cardRoomy)
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
