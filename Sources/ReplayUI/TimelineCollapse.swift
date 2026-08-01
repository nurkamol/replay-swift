import Foundation
import ReplayCore

/// Adjacent gaps of the same kind, shown as one.
///
/// **Presentation, deliberately — the record is not touched.** `timelineItems` in
/// `SessionBuilder` is compared against the reference by the parity suite, and it is right to
/// emit what it emits: a gap, a stretch too short to be a session, and another gap really are
/// three things. What is wrong is *showing* them as three, because the reader is told the same
/// sentence three times about one uninterrupted absence.
///
/// A real day produced five in a row — "11m not recorded", "5m not recorded", "12m not
/// recorded", "5m not recorded", "7m not recorded" — between two sessions, taking more of the
/// page than the sessions they separated. Each one is true. Together they are noise, and they
/// are the loudest thing on a quiet day.
///
/// Only gaps that name no application merge. An `.idle` break carries the app that held focus
/// too long, and two of those in a row are two different applications; folding them would
/// throw away the only fact they carry.
extension Array where Element == TimelineItem {

    func collapsingAdjacentBreaks() -> [TimelineItem] {
        reduce(into: [TimelineItem]()) { result, item in
            guard case .breakItem(let gap) = item,
                  gap.applicationName == nil,
                  case .breakItem(let previous)? = result.last,
                  previous.applicationName == nil,
                  previous.reason == gap.reason
            else {
                result.append(item)
                return
            }
            // The span of the two together, not the sum of their parts: the seconds between
            // them were a stretch too short to be a session, and it was absence too. Summing
            // `seconds` would under-report the hole by exactly the piece that was dropped.
            result[result.count - 1] = .breakItem(
                ActivityBreak(
                    reason: gap.reason,
                    startedAt: previous.startedAt,
                    endedAt: gap.endedAt,
                    seconds: Int((Double(gap.endedAt - previous.startedAt) / 1000).rounded()),
                    applicationName: nil,
                    appPath: nil
                )
            )
        }
    }
}
