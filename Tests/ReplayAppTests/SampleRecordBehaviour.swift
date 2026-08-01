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

    @Test("It produces a record with something in it")
    func hasARecord() {
        let model = SampleRecord.model()
        #expect(model.errorMessage == nil)
        // The *record*, not today. The sample day runs 09:12 to 17:00 and is trimmed at the
        // current moment, so a run at half past midnight writes none of today — correctly,
        // because that day has not happened. This asserted an empty timeline was a failure
        // and duly failed at 00:15, which was the fixture being honest rather than broken.
        #expect(!model.activityByDay().isEmpty)
    }

    @Test("Today is filled once the day it describes has started")
    func todayFillsAsTheDayGoes() {
        // Past the first stretch there must be a today to draw; before it there must not be
        // one invented. Both directions, so this cannot pass by being vacuous at 3am.
        let model = SampleRecord.model()
        let hour = Calendar.current.component(.hour, from: Date())
        let minute = Calendar.current.component(.minute, from: Date())
        let started = hour * 60 + minute > SampleRecord.firstStretchMinute
        #expect(model.timeline.isEmpty != started)
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
        // And a working day only, which this checked for the time but not the date. `seed`
        // marks Saturday and Sunday quiet and drops every other stretch, so a weekend fixture
        // holds about three hours — correct, and less than the four this asserts. The test is
        // named for a working day; it now also runs on one. Found when a Saturday evening
        // crossed 17:00 and turned the suite red for a reason nothing had changed.
        let weekday = Calendar.current.component(.weekday, from: Date())
        guard weekday != 1, weekday != 7 else { return }
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
