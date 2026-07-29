import Foundation
import ReplayCore
import Testing
@testable import ReplayUI

/// The fixture the canvas draws.
///
/// A preview that renders an empty state looks like a preview that works, which is the whole
/// risk here: if `SampleRecord` ever stopped producing sessions — a filter tightened, a
/// rollup changed, the day's stretches falling below the threshold that makes "active" mean
/// something — the canvas would still come up, just blank, and nobody would read that as a
/// broken fixture. So the claim is made here instead, where it can fail out loud.
@MainActor
@Suite("The sample record")
struct SampleRecordBehaviour {

    @Test("It produces a day with something in it")
    func hasADay() {
        let model = SampleRecord.model()
        #expect(model.errorMessage == nil)
        let summary = try? #require(model.summary)
        #expect(summary != nil)
        // Not an assertion about the exact figure — the day is trimmed to now, so an early
        // morning run has less of it than an evening one. Only that it is a day, not a blank.
        #expect(!model.timeline.isEmpty)
    }

    @Test("No stretch is long enough to be read as having walked away")
    func everyStretchCountsAsActive() {
        // The bug this exists for: a day built from hour-long blocks looks like hard work and
        // renders as "46m active", because a run of `idleStretchSeconds` or more is excluded
        // by design. The fixture has to look like a record somebody's Mac would actually make.
        #expect(SampleRecord.longestStretchMinutes * 60 < Rules.idleStretchSeconds)
        // And the day is varied enough to lay out: one app repeated all day would hide every
        // bug that only appears when a name is longer or a row is repeated.
        #expect(SampleRecord.appNames.count >= 5)
    }

    @Test("A full day lands in the hours a working day covers")
    func addsUpToADay() {
        let model = SampleRecord.model()
        // Evening-run only: before 17:00 the day is legitimately still partial, and a test
        // that fails depending on when it runs is worse than one that skips.
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour >= 17 else { return }
        let active = model.summary?.activeSeconds ?? 0
        #expect(active > 4 * 3600)
        #expect(active < 8 * 3600)
    }

    @Test("It never writes the future")
    func stopsAtNow() {
        let model = SampleRecord.model()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for session in model.sessions {
            #expect(session.startedAt <= now)
        }
    }

    @Test("It reaches back far enough for a heatmap to have a shape")
    func hasHistory() {
        let model = SampleRecord.model()
        let byDay = model.activityByDay()
        // More than one day, and not every day identical — a flat grid renders as a bug and
        // this is the fixture that would cause it.
        #expect(byDay.count > 7)
        #expect(Set(byDay.values).count > 1)
    }

    @Test("It goes nowhere near the real record")
    func staysInATemporaryDirectory() {
        let url = SampleRecord.databaseURL()
        #expect(url.path.hasPrefix(NSTemporaryDirectory()))
        #expect(!url.path.contains("Application Support"))
        #expect(url.path != defaultDatabaseURL().path)
        // And two previews do not share one, so a canvas left open cannot accumulate the
        // sample day twice over.
        #expect(SampleRecord.databaseURL() != SampleRecord.databaseURL())
    }
}
