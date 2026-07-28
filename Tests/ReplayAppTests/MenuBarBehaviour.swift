import Foundation
import ReplayCore
import Testing

/// The menu bar popover's decisions.
///
/// The reference has no menu bar — it runs inside the Glaze shell — so nothing here can be
/// contract-checked against it, and these are the only checks this surface will ever get.
/// That is the argument for putting the decisions in `ReplayCore` rather than in the view:
/// a `@MainActor` SwiftUI body is not reachable from a test, and a sentence nobody can
/// assert on is a sentence that drifts.
@Suite("Menu bar popover")
struct MenuBarPopoverBehaviour {

    // MARK: - The day's line

    @Test("A day with nothing in it says so, rather than showing zeroes")
    func emptyDay() {
        #expect(MenuBar.Popover.todayLine(activeSeconds: 0, sessions: 0) == "Nothing recorded yet today.")
    }

    @Test("One session is singular")
    func singular() {
        let line = MenuBar.Popover.todayLine(activeSeconds: 900, sessions: 1)
        #expect(line.contains("1 session"))
        #expect(!line.contains("1 sessions"))
    }

    @Test("More than one is plural")
    func plural() {
        #expect(MenuBar.Popover.todayLine(activeSeconds: 3600, sessions: 4).contains("4 sessions"))
    }

    @Test("A day with sessions but no active time still reports them")
    func sessionsWithoutTime() {
        // Every session was under a minute. "Nothing recorded" would be wrong — something
        // was recorded, it just does not round to a minute.
        #expect(MenuBar.Popover.todayLine(activeSeconds: 0, sessions: 2) != "Nothing recorded yet today.")
    }

    // MARK: - The goal

    @Test("Short of the goal, it says what is left")
    func goalRemaining() {
        // 1h done against a 3h goal: two hours to go.
        let line = MenuBar.Popover.goalLine(activeSeconds: 3600, goalMinutes: 180)
        #expect(line == "2h to go of 3 hours")
    }

    @Test("At the goal, it stops counting")
    func goalMet() {
        let line = MenuBar.Popover.goalLine(activeSeconds: 10_800, goalMinutes: 180)
        #expect(line.hasPrefix("Goal reached"))
    }

    @Test("Past the goal it still says reached, never a figure over 100%")
    func goalExceeded() {
        // SPEC §8: the app describes rather than grades. A number that keeps climbing past
        // the target invites reading a finished day as still not enough.
        let line = MenuBar.Popover.goalLine(activeSeconds: 40_000, goalMinutes: 180)
        #expect(line.hasPrefix("Goal reached"))
        #expect(!line.contains("%"))
        #expect(!line.contains("to go"))
    }

    @Test("A goal exactly met counts as met")
    func goalExact() {
        #expect(MenuBar.Popover.goalLine(activeSeconds: 1800, goalMinutes: 30).hasPrefix("Goal reached"))
    }

    // MARK: - Recent sessions

    private func session(startedAt: Int64, title: String) -> ActivitySession {
        ActivitySession(
            title: title, category: .development, startedAt: startedAt,
            endedAt: startedAt + 600_000, spanSeconds: 600, activeSeconds: 600,
            apps: [], events: [], switches: 0
        )
    }

    @Test("Newest first, because the popover is read top-down")
    func newestFirst() {
        let rows = [
            session(startedAt: 1_000, title: "first"),
            session(startedAt: 3_000, title: "third"),
            session(startedAt: 2_000, title: "second"),
        ]
        #expect(MenuBar.Popover.sessions(in: rows).map(\.title) == ["third", "second", "first"])
    }

    @Test("Never more than the limit, whatever the day held")
    func capped() {
        let rows = (0..<40).map { session(startedAt: Int64($0) * 1_000, title: "s\($0)") }
        #expect(MenuBar.Popover.sessions(in: rows).count == MenuBar.Popover.sessionLimit)
    }

    @Test("Fewer than the limit is fine, and is not padded")
    func short() {
        #expect(MenuBar.Popover.sessions(in: [session(startedAt: 1, title: "only")]).count == 1)
        #expect(MenuBar.Popover.sessions(in: []).isEmpty)
    }

    @Test("The limit fits on a screen without scrolling")
    func limitIsSmall() {
        // The ceiling is the design. This is read mid-task; a list you have to scroll is a
        // worse Timeline rather than a quicker one.
        #expect(MenuBar.Popover.sessionLimit <= 4)
    }

    // MARK: - The control

    @Test("The pause control is a verb, and says what pressing it does")
    func trackingLabel() {
        #expect(MenuBar.Popover.trackingLabel(isRecording: true) == "Pause recording")
        #expect(MenuBar.Popover.trackingLabel(isRecording: false) == "Resume recording")
    }

    // MARK: - How long you have been in it

    @Test("Under a minute is not a sentence with 'just now' wedged into it")
    func focusedForShort() {
        // "Focused for just now" is what composing this out of shortDuration produced. It
        // read fine as a standalone menu row and only became wrong under an app's name.
        #expect(MenuBar.focusedFor(0) == "Just now")
        #expect(MenuBar.focusedFor(20) == "Just now")
    }

    @Test("A minute or more reads as a duration")
    func focusedForLong() {
        #expect(MenuBar.focusedFor(60) == "Focused for 1m")
        #expect(MenuBar.focusedFor(3600) == "Focused for 1h")
        #expect(MenuBar.focusedFor(5400) == "Focused for 1h 30m")
    }

    // MARK: - What the menu already answered, still answered

    @Test("Paused beats away, and away beats whatever the tracker last saw")
    func stateOrder() {
        let current = (applicationName: "Xcode", startedAt: Int64(0))
        #expect(MenuBar.now(isRecording: false, isAway: true, current: current, now: 60_000) == .paused)
        #expect(MenuBar.now(isRecording: true, isAway: true, current: current, now: 60_000) == .away)
        #expect(
            MenuBar.now(isRecording: true, isAway: false, current: current, now: 60_000)
                == .inApplication(name: "Xcode", seconds: 60)
        )
        #expect(MenuBar.now(isRecording: true, isAway: false, current: nil, now: 60_000) == .waiting)
    }
}
