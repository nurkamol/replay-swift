import ReplayCore
import SwiftUI

/// The Timeline: your recent days, newest first.
///
/// Today answers "what has today been". The Timeline is the archive — the same sessions,
/// grouped by the day they began, with the quiet gaps left in so the shape of a day is
/// legible. It describes; it does not grade. A day with nothing on it simply is not there.
struct TimelineView: View {
    let history: HistoryModel
    let annotations: AnnotationsModel
    /// Given so a day can be opened from its ⋯ menu.
    let onOpenDay: (Int64) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if history.days.isEmpty {
                    empty
                } else {
                    ForEach(history.days) { day in
                        DaySection(
                            day: day,
                            history: history,
                            annotations: annotations,
                            onOpenDay: onOpenDay
                        )
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Timeline")
                    .font(.system(size: 28, weight: .bold))
                Text(history.range.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Picker("Range", selection: Binding(
                get: { history.range },
                set: { history.range = $0 }
            )) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(history.range == .today ? "A quiet day" : "No history yet")
                .font(.headline)
            Text(emptyDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 40)
    }

    private var emptyDetail: String {
        switch history.range {
        case .today: "Nothing recorded yet today — your sessions will appear here as you work."
        case .yesterday: "Replay didn't record anything yesterday."
        case .week, .month:
            "Replay keeps your recent history. Your first sessions will appear here as you work."
        }
    }
}

/// One day in the Timeline: its divider, its actions, and everything that happened on it.
private struct DaySection: View {
    let day: TimelineDay
    let history: HistoryModel
    let annotations: AnnotationsModel
    let onOpenDay: (Int64) -> Void

    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ForEach(Array(day.items.enumerated()), id: \.offset) { index, item in
                // A quiet rule where the day turns over. Not per-hour: sessions routinely
                // span two or three hours, so an hour rule between every pair would
                // out-number the sessions it was meant to organise.
                if let part = partBreak(at: index) {
                    PartDivider(part: part)
                }
                switch item {
                case .session(let session):
                    SessionCard(
                        session: session,
                        annotations: annotations,
                        onDelete: { history.deleteSession(session) }
                    )
                case .breakItem(let gap):
                    BreakRow(gap: gap)
                }
            }
        }
        .confirmationDialog(
            "Delete \(day.label)?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Day", role: .destructive) { history.deleteDay(day.dayStart) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Deleting \(day.label) permanently removes its sessions, its summary, and any "
                    + "notes or bookmarks on it. Every other day is left untouched, and this "
                    + "can't be undone."
            )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(day.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.6)
                .fixedSize()

            Rectangle().fill(.quaternary).frame(height: 1)

            Text(formatDurationShort(day.activeSeconds))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .fixedSize()

            // Gathered behind one button rather than sitting inline: a permanent destructive
            // control beside every day is easy to hit by accident, and noisy for something
            // rarely wanted.
            Menu {
                Button("Open This Day") { onOpenDay(day.dayStart) }
                Divider()
                Button("Delete This Day…", role: .destructive) { confirmingDelete = true }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    /// The day-part label to draw above this item, or `nil` when it is still the same part
    /// as the item before it.
    private func partBreak(at index: Int) -> String? {
        let part = dayPart(of: startedAt(day.items[index]))
        guard index > 0 else { return part }
        return dayPart(of: startedAt(day.items[index - 1])) == part ? nil : part
    }

    private func startedAt(_ item: TimelineItem) -> Int64 {
        switch item {
        case .session(let session): session.startedAt
        case .breakItem(let gap): gap.startedAt
        }
    }
}

private struct PartDivider: View {
    let part: String

    var body: some View {
        HStack(spacing: 8) {
            Text(part)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .kerning(0.5)
            Rectangle().fill(.quaternary.opacity(0.6)).frame(height: 1)
        }
        .padding(.top, 4)
    }
}

/// One day from the past, reopened.
///
/// The same sessions the Timeline builds, for a single fixed day. When the rows are gone —
/// pruned past the retention window — it says so plainly rather than pretending the day was
/// empty, because the day's headline is still there to prove otherwise.
struct DayView: View {
    let day: TimelineDay
    let headline: DailySummary?
    let annotations: AnnotationsModel
    let onDeleteSession: (ActivitySession) -> Void
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if day.items.isEmpty {
                    pruned
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(day.sessions.count) \(day.sessions.count == 1 ? "session" : "sessions")")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .kerning(0.6)

                        ForEach(Array(day.items.enumerated()), id: \.offset) { _, item in
                            switch item {
                            case .session(let session):
                                SessionCard(
                                    session: session,
                                    annotations: annotations,
                                    onDelete: { onDeleteSession(session) }
                                )
                            case .breakItem(let gap):
                                BreakRow(gap: gap)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onBack) {
                Label("Timeline", systemImage: "chevron.left")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(fullDayLabel(day.dayStart))
                    .font(.system(size: 28, weight: .bold))
                if !day.items.isEmpty {
                    Text("\(formatDurationShort(day.activeSeconds)) active")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var pruned: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No timeline for this day")
                .font(.headline)
            Text(prunedDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 40)
    }

    /// The headline is what survives pruning, so when there is one the day was not empty —
    /// it is simply older than the kept history, and saying "nothing happened" would be a lie.
    private var prunedDetail: String {
        if let headline, headline.activeSeconds > 0 {
            let top = headline.topAppName.map { " Most of it was \($0)." } ?? ""
            return "This day is older than your kept history. Its summary survives: "
                + "\(formatDurationShort(headline.activeSeconds)) active.\(top)"
        }
        return "Either nothing was recorded, or this day is older than your kept history."
    }
}
