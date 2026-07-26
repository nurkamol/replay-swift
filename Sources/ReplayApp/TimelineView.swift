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
    let export: ExportModel
    /// Given so a day can be opened from its ⋯ menu.
    let onOpenDay: (Int64) -> Void

    @Environment(\.motion) private var motion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.block) {
                if history.days.isEmpty {
                    empty.centredInPage()
                } else {
                    ForEach(history.days) { day in
                        DaySection(
                            day: day,
                            history: history,
                            annotations: annotations,
                            export: export,
                            onOpenDay: onOpenDay
                        )
                    }
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle("Timeline")
        .navigationSubtitle(history.range.subtitle)
        .toolbar {
            // The range belongs in the chrome rather than the content: it governs the whole
            // surface, and a control that scrolls away with what it controls is a control
            // you have to go looking for.
            ToolbarItem(placement: .principal) {
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
                .help("How much history the Timeline shows")
            }
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(
                history.range == .today ? "A quiet day" : "No history yet",
                systemImage: "calendar.day.timeline.left"
            )
        } description: {
            Text(emptyDetail)
        }
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
    @Environment(\.motion) private var motion
    let day: TimelineDay
    let history: HistoryModel
    let annotations: AnnotationsModel
    let export: ExportModel
    let onOpenDay: (Int64) -> Void

    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
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
                        export: export,
                        onDelete: { history.deleteSession(session) }
                    )
                    .settlesIntoView(reduced: motion.reduced)
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
        HStack(spacing: Design.Space.row) {
            Text(day.label)
                .font(Design.Text.sectionLabel)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(Design.Text.labelKerning)
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
                Menu("Export This Day") {
                    ForEach(Report.Format.allCases, id: \.self) { format in
                        Button(format.label) {
                            // Named by its date, not by "Today": a file called "Replay
                            // Today" stops being true tomorrow.
                            export.exportReport(
                                format, label: fullDayLabel(day.dayStart), sessions: day.sessions
                            )
                        }
                    }
                }
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
        HStack(spacing: Design.Space.inline) {
            Text(part)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .kerning(Design.Text.tightKerning)
            Rectangle().fill(Design.Colour.divider).frame(height: 1)
        }
        .padding(.top, Design.Space.tight)
    }
}

/// One day from the past, reopened.
///
/// The same sessions the Timeline builds, for a single fixed day. When the rows are gone —
/// pruned past the retention window — it says so plainly rather than pretending the day was
/// empty, because the day's headline is still there to prove otherwise.
struct DayView: View {
    @Environment(\.motion) private var motion
    let day: TimelineDay
    let headline: DailySummary?
    let reflection: Reflection
    let annotations: AnnotationsModel
    let export: ExportModel
    let onReflect: (String) -> Void
    let onDeleteSession: (ActivitySession) -> Void

    private var story: [String] { DayStory.build(day.sessions) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.block) {
                header

                // The day in a few sentences, when it can support them. A thin day gets
                // none rather than a padded one — see DayStory.
                if !story.isEmpty {
                    VStack(alignment: .leading, spacing: Design.Space.snug) {
                        Text("The story of this day")
                            .font(Design.Text.cardLabel)
                            .foregroundStyle(.tertiary)
                            .kerning(Design.Text.labelKerning)
                            .textCase(.uppercase)
                        Text(story.joined(separator: " "))
                            .font(Design.Text.prose)
                            .lineSpacing(Design.Text.proseLineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Design.Space.section)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Design.Colour.surface, in: RoundedRectangle(cornerRadius: Design.Radius.card))
                }

                // Offered even on a day whose rows were pruned: what you wrote about a day
                // outlives the activity behind it, and is often the only thing left.
                ReflectionCard(
                    dayStart: day.dayStart,
                    reflection: reflection,
                    prompt: "What do you want to remember about this day?",
                    onCommit: onReflect
                )

                if day.items.isEmpty {
                    pruned
                } else {
                    VStack(alignment: .leading, spacing: Design.Space.row) {
                        HStack {
                            Text("\(day.sessions.count) \(day.sessions.count == 1 ? "session" : "sessions")")
                                .font(Design.Text.sectionLabel)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .kerning(Design.Text.labelKerning)
                            Spacer()
                            Menu("Export…") {
                                ForEach(Report.Format.allCases, id: \.self) { format in
                                    Button(format.label) {
                                        export.exportReport(
                                            format,
                                            label: fullDayLabel(day.dayStart),
                                            sessions: day.sessions
                                        )
                                    }
                                }
                            }
                            .menuStyle(.button)
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .fixedSize()
                        }

                        ForEach(Array(day.items.enumerated()), id: \.offset) { _, item in
                            switch item {
                            case .session(let session):
                                SessionCard(
                                    session: session,
                                    annotations: annotations,
                                    export: export,
                                    onDelete: { onDeleteSession(session) }
                                )
                    .settlesIntoView(reduced: motion.reduced)
                            case .breakItem(let gap):
                                BreakRow(gap: gap)
                            }
                        }
                    }
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle(fullDayLabel(day.dayStart))
        .navigationSubtitle(
            day.items.isEmpty ? "" : "\(formatDurationShort(day.activeSeconds)) active"
        )
        .toolbar {
            if !day.sessions.isEmpty {
                ToolbarItem {
                    Menu {
                        ForEach(Report.Format.allCases, id: \.self) { format in
                            Button(format.label) {
                                export.exportReport(
                                    format,
                                    label: fullDayLabel(day.dayStart),
                                    sessions: day.sessions
                                )
                            }
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .help("Export this day")
                }
            }
        }
    }

    /// No back button of its own: the navigation stack draws one, and ⌘[ works because it
    /// is the system's rather than a `Button` that happens to look like it.
    private var header: some View {
        VStack(alignment: .leading, spacing: Design.Space.hairline) {
            Text(fullDayLabel(day.dayStart))
                .font(Design.Text.title)
            if !day.items.isEmpty {
                Text("\(formatDurationShort(day.activeSeconds)) active")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pruned: some View {
        VStack(alignment: .leading, spacing: Design.Space.snug) {
            Text("No timeline for this day")
                .font(.headline)
            Text(prunedDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Design.Space.emptyStateRoomy)
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
