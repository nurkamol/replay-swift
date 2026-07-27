import Foundation
import Observation
import ReplayCore

/// The last seven days, aggregated.
///
/// The seven local midnights ending today are chosen here rather than in `computeWeekSummary`:
/// the view owns the calendar and the aggregation only fills in the days being looked at. That
/// is why a day with nothing recorded still appears — as rest, not as a missing row.
@MainActor
@Observable
final class WeekModel {
    private(set) var summary: WeekSummary?
    /// The recurring application combinations behind the same seven days. Capped at four:
    /// this is a note about how the week went, not a catalogue.
    private(set) var workflows: [Workflow] = []
    private(set) var errorMessage: String?

    /// "February 2 – February 8" — the span, named the way a person would say it.
    private(set) var rangeLabel = ""

    private let model: AppModel
    private var store: ActivityStore { model.store }

    init(model: AppModel) {
        self.model = model
    }

    func load() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let today = startOfLocalDay(now)
        let dayStarts = (0..<7).map { today - Int64(6 - $0) * dayMillis }

        do {
            let events = try store.sessions(from: dayStarts[0], to: today + dayMillis)
            summary = computeWeekSummary(events: events, dayStarts: dayStarts, now: now)
            workflows = Array(detectWorkflows(sessionsForWeek(events, now: now)).prefix(WeekSummary.workflowLimit))
            rangeLabel = Self.range(from: dayStarts[0], to: dayStarts[6])
            errorMessage = nil
        } catch {
            errorMessage = "\(error)"
        }
    }

    private static func range(from: Int64, to: Int64) -> String {
        let format = Date.FormatStyle.dateTime.month(.wide).day()
        let first = Date(timeIntervalSince1970: Double(from) / 1000).formatted(format)
        let last = Date(timeIntervalSince1970: Double(to) / 1000).formatted(format)
        return "\(first) – \(last)"
    }
}
