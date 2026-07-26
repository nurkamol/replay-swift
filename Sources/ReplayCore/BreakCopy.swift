/// What a gap in the day is called.
///
/// Here rather than in the view for one reason: the words are the product. SPEC §8 says
/// this app describes and never grades, and a gap is where that is easiest to break —
/// "8m not recorded" is a fact, "8m wasted" is a verdict. Copy that lives in a view is
/// copy nothing checks, and this port had already drifted from the reference in three
/// places before the contract covered it: idle read "2m idle in Safari" instead of
/// "2m break", its detail invented "One app held focus without input", and an editorial
/// comma had crept into the unrecorded line.
///
/// The strings are now generated into `spec/grouping-and-export.json` from the reference's
/// own `describeBreak`, so the next drift fails the suite instead of shipping.
public struct BreakDescription: Equatable, Sendable {
    /// The figure and what it was — the line that carries the meaning.
    public let title: String
    /// Why the gap exists, in support of the title.
    public let detail: String
}

public func describeBreak(_ item: ActivityBreak) -> BreakDescription {
    let length = formatDurationShort(item.seconds)
    switch item.reason {
    case .unrecorded:
        // A right single quote, not an apostrophe: the reference uses the typographic
        // one, and this is a contract check, so the character matters.
        return BreakDescription(
            title: "\(length) not recorded",
            detail: "Replay wasn\u{2019}t running or tracking was paused"
        )
    case .away:
        return BreakDescription(
            title: "\(length) away",
            detail: "No keyboard or mouse activity"
        )
    case .idle:
        // Named "break" rather than "idle": what the user sees is that nothing changed,
        // not a judgement about whether they were working.
        return BreakDescription(
            title: "\(length) break",
            detail: item.applicationName.map { "\($0) stayed in front, no switching" }
                ?? "No app switching"
        )
    }
}
