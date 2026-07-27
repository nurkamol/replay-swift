import ReplayCore
import SwiftUI

/// What you were doing on this date before.
///
/// Reads only the durable daily headlines, which is why it keeps working on days whose raw
/// events have been pruned — a memory from two years ago is often the *only* thing left of
/// that day, and showing it is what those headlines are kept for.
@MainActor
@Observable
final class MemoriesModel {
    private(set) var memories: [Memories.Memory] = []
    /// The things worth rediscovering, and the days they fell on.
    private(set) var moments: [Moment] = []
    /// Active seconds per day across the last two years, for the heatmap.
    private(set) var byDay: [Int64: Int] = [:]
    /// The days a surprise can land on.
    private(set) var pool: [Int64] = []
    private(set) var loaded = false

    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func load() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let from = startOfLocalDay(now) - Int64(Memories.lookbackDays) * dayMillis
        let summaries = (try? model.store.dailySummaries(from: from, to: now + dayMillis)) ?? []
        memories = Memories.find(in: summaries, now: now)

        // Moments reach back further than the memory window does: they read the durable
        // headlines, which outlive the rows.
        let all = (try? model.store.dailySummaries(from: 0, to: now + dayMillis)) ?? []
        let recent = (try? model.store.sessions(
            from: startOfLocalDay(now) - 29 * dayMillis, to: now + dayMillis
        )) ?? []
        moments = detectMoments(
            seed: try? model.store.momentSeed(),
            summaries: all, events: recent, now: now
        )

        let bookmarks = ((try? model.store.annotations(from: 0, to: now + dayMillis)) ?? [])
            .filter(\.bookmarked)
            .map(\.sessionStart)
        pool = surprisePool(
            moments: moments, summaries: all, bookmarkStarts: bookmarks, now: now
        )

        byDay = Dictionary(
            all.map { ($0.dayStart, $0.activeSeconds) },
            uniquingKeysWith: { first, _ in first }
        )
        loaded = true
    }

    /// A day worth arriving on, or nothing when there is no history to surprise with.
    ///
    /// Genuinely random rather than seeded: the point of the button is that you do not know
    /// where it goes, and a "random" that repeated would stop being one.
    func surprise() -> Int64? { pool.randomElement() }
}

/// The list of them, and a card for Today when there is one worth showing.
struct MemoriesView: View {
    let memories: MemoriesModel
    let onOpenDay: (Int64) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.block) {
                if memories.memories.isEmpty && memories.moments.isEmpty {
                    empty.centredInPage()
                } else {
                    surpriseButton
                    if !memories.moments.isEmpty { momentsSection }
                    if !memories.memories.isEmpty {
                        VStack(alignment: .leading, spacing: Design.Space.row) {
                            Text("On this day").sectionLabelStyle()
                            ForEach(memories.memories, id: \.range.key) { memory in
                                MemoryRow(
                                    memory: memory,
                                    onOpen: { onOpenDay(memory.range.dayStart) }
                                )
                            }
                        }
                    }
                    if !memories.byDay.isEmpty { heatmapSection }
                    Text("Everything here is built on this Mac, from your own history.")
                        .font(Design.Text.detail)
                        .foregroundStyle(.tertiary)
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle("Memories")
        .navigationSubtitle("What you were doing on this date before")
        .onAppear { memories.load() }
    }

    /// One button that goes somewhere you did not choose.
    private var surpriseButton: some View {
        Button {
            if let day = memories.surprise() { onOpenDay(day) }
        } label: {
            Label("Surprise me", systemImage: "shuffle")
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Space.row)
                .contentShape(Rectangle())
        }
        .buttonStyle(.row)
        .card(border: Design.Colour.border)
        .disabled(memories.pool.isEmpty)
        .help("Open a day worth rediscovering")
    }

    private var momentsSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text("Moments").sectionLabelStyle()
            VStack(spacing: Design.Space.snug) {
                ForEach(memories.moments, id: \.key) { moment in
                    Button {
                        if let day = moment.dayStart { onOpenDay(day) }
                    } label: {
                        HStack(spacing: Design.Space.card) {
                            Image(systemName: glyph(for: moment.kind))
                                .font(Design.Text.prose)
                                .foregroundStyle(.tint)
                                .frame(width: Design.Icon.glyphColumn)
                            VStack(alignment: .leading, spacing: Design.Space.hairline) {
                                Text(moment.title).font(Design.Text.itemTitle)
                                Text(moment.detail)
                                    .font(Design.Text.detail)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: Design.Space.inline)
                            if moment.dayStart != nil {
                                Image(systemName: "chevron.right")
                                    .font(Design.Text.micro)
                                    .foregroundStyle(.quaternary)
                            }
                        }
                        .padding(Design.Space.section)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.row)
                    .disabled(moment.dayStart == nil)
                    .card(border: Design.Colour.borderQuiet)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text("Browse by date").sectionLabelStyle()
            Heatmap(byDay: memories.byDay, onOpenDay: onOpenDay)
                .padding(Design.Space.section)
                .card(border: Design.Colour.borderQuiet)
        }
    }

    private func glyph(for kind: Moment.Kind) -> String {
        switch kind {
        case .longestFocus: "hourglass"
        case .peakDay: "arrow.up.forward.app"
        case .busyMix: "square.grid.2x2"
        case .nightOwl: "moon"
        case .streak: "calendar.badge.checkmark"
        case .newApp: "sparkles"
        case .origin: "flag"
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("Nothing to look back on yet", systemImage: "clock.arrow.circlepath")
        } description: {
            Text(
                "Replay looks at the same date a week, a month, and up to two years ago. "
                    + "A memory keeps appearing after the raw activity has been pruned, "
                    + "because a day's headline outlives it."
            )
        }
    }
}

private struct MemoryRow: View {
    let memory: Memories.Memory
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Design.Space.card) {
                VStack(alignment: .leading, spacing: Design.Space.hairline) {
                    Text(memory.range.label)
                        .font(Design.Text.cardLabel)
                        .foregroundStyle(.tertiary)
                        .kerning(Design.Text.labelKerning)
                        .textCase(.uppercase)
                    Text(fullDayLabel(memory.range.dayStart))
                        .font(Design.Text.itemTitle)
                    if let top = memory.summary.topAppName {
                        Text("Mostly \(top)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(formatDurationShort(memory.summary.activeSeconds))
                    .font(Design.Text.figure)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(Design.Space.cardRoomy)
            .contentShape(Rectangle())
        }
        .buttonStyle(.row)
        .card(border: Design.Colour.fillStrong)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(memory.range.label), \(fullDayLabel(memory.range.dayStart)), "
                + "\(formatDurationShort(memory.summary.activeSeconds)) active"
                + (memory.summary.topAppName.map { ", mostly \($0)" } ?? "")
        )
        .accessibilityHint("Opens that day")
    }
}

/// The nearest memory, on Today.
///
/// One, not a list: Today is about today, and a whole gallery of the past on it would be a
/// different app. It links to the rest.
struct TodayInHistoryCard: View {
    let memory: Memories.Memory
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Design.Space.card) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(memory.range.label)
                        .font(Design.Text.cardLabel)
                        .foregroundStyle(.tertiary)
                        .kerning(Design.Text.labelKerning)
                        .textCase(.uppercase)
                    Text(detail)
                        .font(.callout)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(Design.Space.cardRoomy)
            .contentShape(Rectangle())
        }
        .buttonStyle(.row)
        .card(background: Design.Colour.surface, border: Design.Colour.fill)
    }

    /// States what is actually known and no more: the headline has a total and a top app,
    /// so the sentence has a total and a top app.
    private var detail: String {
        let active = formatDurationShort(memory.summary.activeSeconds)
        if let top = memory.summary.topAppName {
            return "\(active) active, mostly \(top)"
        }
        return "\(active) active"
    }
}

/// A year of days, as a grid.
///
/// One square per day, weight by how much was in it — the shape of a year at a glance, and a
/// way into any day of it. Empty squares are drawn rather than skipped: the gaps are the
/// point as much as the fills.
struct Heatmap: View {
    @Environment(\.themeTint) private var tint
    let byDay: [Int64: Int]
    let onOpenDay: (Int64) -> Void

    @State private var hovered: Int64?

    /// The busiest day, which everything else is measured against — a fixed ceiling would
    /// make a quiet year look empty and a heavy one look uniform.
    private var busiest: Int { max(byDay.values.max() ?? 1, 1) }

    var body: some View {
        // Whole weeks, ending with the one today falls in, so the columns line up.
        let today = startOfLocalDay(Int64(Date().timeIntervalSince1970 * 1000))
        let weeks = (0..<Design.Layout.heatmapWeeks).reversed().map { back -> [Int64] in
            let end = today - Int64(back) * 7 * dayMillis
            return (0..<7).map { end - Int64(6 - $0) * dayMillis }
        }
        return VStack(alignment: .leading, spacing: Design.Space.inline) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Design.Layout.heatmapGap) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: Design.Layout.heatmapGap) {
                            ForEach(week, id: \.self) { day in
                                square(day, upTo: today)
                            }
                        }
                    }
                }
                .padding(.vertical, Design.Space.tight)
            }
            .defaultScrollAnchor(.trailing)

            HStack(spacing: Design.Space.snug) {
                if let hovered, let seconds = byDay[hovered], seconds > 0 {
                    Text("\(fullDayLabel(hovered)) · \(formatDurationShort(seconds))")
                        .font(Design.Text.micro)
                        .foregroundStyle(.secondary)
                } else {
                    Text("A year of days. Darker is quieter.")
                        .font(Design.Text.micro)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "A grid of the last year. \(byDay.values.filter { $0 > 0 }.count) days recorded."
        )
    }

    private func square(_ day: Int64, upTo today: Int64) -> some View {
        let seconds = byDay[day] ?? 0
        let fraction = Double(seconds) / Double(busiest)
        // Square-rooted, because the eye compares area: a linear scale makes one heavy day
        // wash out a month of ordinary ones.
        let weight = seconds == 0 ? 0 : Design.Colour.heatFloor
            + fraction.squareRoot() * Design.Colour.heatRange
        return RoundedRectangle(cornerRadius: Design.Radius.hair, style: .continuous)
            .fill(seconds == 0 ? Design.Colour.fill : AnyShapeStyle(tint.opacity(weight)))
            .frame(width: Design.Layout.heatmapSquare, height: Design.Layout.heatmapSquare)
            // Days that have not happened yet are absent rather than empty.
            .opacity(day > today ? 0 : 1)
            .onHover { hovered = $0 ? day : nil }
            .onTapGesture { if seconds > 0 { onOpenDay(day) } }
    }
}
