import Foundation
import Testing

@testable import ReplayCore
@testable import ReplayUI

/// Runs of identical gap rows, shown as one.
///
/// A real day produced five "not recorded" rows in a row between two sessions, together
/// taking more of the page than the sessions they separated. Each was true; the repetition
/// was the problem.
@Suite("Collapsing adjacent breaks")
struct TimelineCollapseBehaviour {

    private func gap(
        _ reason: BreakReason, from: Int64, to: Int64, app: String? = nil
    ) -> TimelineItem {
        .breakItem(
            ActivityBreak(
                reason: reason, startedAt: from, endedAt: to,
                seconds: Int((Double(to - from) / 1000).rounded()),
                applicationName: app, appPath: nil
            )
        )
    }

    @Test("A run of the same kind becomes one row spanning all of it")
    func mergesARun() {
        let items: [TimelineItem] = [
            gap(.unrecorded, from: 0, to: 60_000),
            gap(.unrecorded, from: 90_000, to: 150_000),
            gap(.unrecorded, from: 200_000, to: 260_000),
        ]
        let collapsed = items.collapsingAdjacentBreaks()
        #expect(collapsed.count == 1)
        guard case .breakItem(let only)? = collapsed.first else { Issue.record("no break"); return }
        #expect(only.startedAt == 0)
        #expect(only.endedAt == 260_000)
        // The span, not the sum of the parts. The stretches *between* the gaps were too short
        // to be sessions and were dropped — they were absence too, and summing `seconds`
        // would under-report the hole by exactly the piece that was thrown away.
        #expect(only.seconds == 260)
        #expect(only.seconds > 60 + 60 + 60)
    }

    @Test("Different kinds stay apart, because they mean different things")
    func doesNotMergeAcrossReasons() {
        let items: [TimelineItem] = [
            gap(.away, from: 0, to: 60_000),
            gap(.unrecorded, from: 60_000, to: 120_000),
        ]
        #expect(items.collapsingAdjacentBreaks().count == 2)
    }

    /// An `.idle` break names the application that held focus too long, and two in a row are
    /// two different applications. Folding them would throw away the only fact they carry.
    @Test("A gap that names an application is never folded into another")
    func keepsNamedGaps() {
        let items: [TimelineItem] = [
            gap(.idle, from: 0, to: 60_000, app: "Xcode"),
            gap(.idle, from: 60_000, to: 120_000, app: "Firefox"),
        ]
        #expect(items.collapsingAdjacentBreaks().count == 2)
    }

    @Test("Sessions between gaps keep them apart")
    func sessionsInterrupt() {
        let session = TimelineItem.session(
            ActivitySession(
                title: "A", category: .development, startedAt: 60_000, endedAt: 90_000,
                spanSeconds: 30, activeSeconds: 30, apps: [], events: [], switches: 0
            )
        )
        let items: [TimelineItem] = [
            gap(.unrecorded, from: 0, to: 60_000),
            session,
            gap(.unrecorded, from: 90_000, to: 150_000),
        ]
        #expect(items.collapsingAdjacentBreaks().count == 3)
    }

    @Test("A list with nothing to merge comes back unchanged")
    func leavesOthersAlone() {
        let items: [TimelineItem] = [gap(.unrecorded, from: 0, to: 60_000)]
        #expect(items.collapsingAdjacentBreaks().count == 1)
        #expect([TimelineItem]().collapsingAdjacentBreaks().isEmpty)
    }
}
