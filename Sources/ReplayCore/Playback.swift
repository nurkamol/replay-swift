import Foundation

/// The virtual clock behind playing a day back.
///
/// A whole day runs in half a minute whatever it held, which is what makes it watchable: a
/// playback proportional to the day would be four minutes for a heavy one and eight seconds
/// for a quiet one. The clock is the day's own span mapped onto that fixed length, so the
/// gaps between sessions are still felt — a morning with nothing in it passes as a pause,
/// not as a cut.
///
/// Ported from `playback.tsx` in the Glaze app.
public enum Playback {
    /// How long one pass takes at the ordinary speed.
    public static let baseDurationMillis = 32_000
    /// The speeds offered. A day at five times is a flick through rather than a watch.
    public static let speeds = [1, 2, 5]

    /// A day queued up to watch: the sessions, and what to call it while it plays.
    ///
    /// The label travels with the sessions rather than being decided by the screen showing
    /// them. It was hard-coded to "Today" when today was the only day you could watch, and
    /// that is exactly the kind of assumption that survives a feature it stopped being true
    /// for — a Tuesday in April played back under the word "Today".
    public struct Day: Equatable, Sendable {
        public var sessions: [ActivitySession]
        public var label: String

        public init(sessions: [ActivitySession], label: String) {
            self.sessions = sessions
            self.label = label
        }
    }

    /// The span a set of sessions covers: from the first start to the last end.
    public static func span(_ sessions: [ActivitySession]) -> (start: Int64, end: Int64) {
        guard let start = sessions.first?.startedAt else { return (0, 1) }
        let end = sessions.map(\.endedAt).max() ?? start
        return (start, max(start + 1, end))
    }

    /// The instant a progress of 0–1 lands on.
    public static func time(at progress: Double, in sessions: [ActivitySession]) -> Int64 {
        let bounds = span(sessions)
        let clamped = min(1, max(0, progress))
        return bounds.start + Int64(Double(bounds.end - bounds.start) * clamped)
    }

    /// The session on screen at a given progress.
    ///
    /// The one containing that instant, or — when the playhead is in a gap — the last one
    /// that has already happened, so the screen holds the moment you were in rather than
    /// going blank between them.
    public static func session(
        at progress: Double, in sessions: [ActivitySession]
    ) -> ActivitySession? {
        guard !sessions.isEmpty else { return nil }
        let now = time(at: progress, in: sessions)
        if let containing = sessions.first(where: { $0.startedAt <= now && now <= $0.endedAt }) {
            return containing
        }
        return sessions.last { $0.startedAt <= now } ?? sessions.first
    }

    /// Where along the day a session sits, 0–1 — for placing it on the filmstrip.
    public static func offset(of session: ActivitySession, in sessions: [ActivitySession]) -> Double {
        let bounds = span(sessions)
        let width = Double(bounds.end - bounds.start)
        guard width > 0 else { return 0 }
        return Double(session.startedAt - bounds.start) / width
    }
}
