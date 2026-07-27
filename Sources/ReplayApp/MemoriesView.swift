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
                // Memories arrived whole where every other surface assembles. Nothing
                // here was staggered at all, so switching to it after Today or the
                // Timeline read as a jump rather than as a screen being entered.
                surpriseButton
                    .settlesIn(0)
                if !memories.moments.isEmpty { momentsSection.settlesIn(1) }

                VStack(alignment: .leading, spacing: Design.Space.row) {
                    Text("On this day").sectionLabelStyle()
                    if memories.memories.isEmpty {
                        // Emptiness here is a section, not a screen. The whole-page version
                        // this replaces took the heatmap and Surprise down with it, so a new
                        // user — the only person who ever saw it — was told to browse and
                        // then given nothing to browse with.
                        noMemoriesYet
                    } else {
                        ForEach(Array(memories.memories.enumerated()), id: \.element.range.key) {
                            index, memory in
                            MemoryRow(
                                memory: memory,
                                onOpen: { onOpenDay(memory.range.dayStart) }
                            )
                            // Each card on its own beat, as upstream. Applied to the list
                            // rather than the section, which arrived as one block.
                            .settlesIn(index)
                        }
                    }
                }
                .settlesIn(2)

                if !memories.byDay.isEmpty { heatmapSection.settlesIn(3) }
                localOnly.settlesIn(4)
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

    /// No memories *for this date* — which is not the same as no history, and says so.
    private var noMemoriesYet: some View {
        VStack(spacing: Design.Space.hairline) {
            Text("No memories for this date yet")
                .font(Design.Text.itemTitle)
            Text(
                "Replay will begin building your personal history every day. This date will "
                    + "start to fill with the days that came before it — until then, browse "
                    + "any day below."
            )
            .font(Design.Text.detail)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Design.Space.cardRoomy)
        .frame(maxWidth: .infinity)
        .card(border: Design.Colour.borderQuiet)
    }

    /// The claim the whole feature rests on, said plainly at the foot of it.
    private var localOnly: some View {
        HStack(spacing: Design.Space.snug) {
            Spacer(minLength: 0)
            Image(systemName: "lock")
                .font(Design.Text.micro)
            Text("All memories are generated locally. Nothing is uploaded.")
                .font(Design.Text.micro)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.tertiary)
        .accessibilityElement(children: .combine)
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

/// Your days as squares — a week, a month, or a year of them.
///
/// One square per day, shaded by how much it held, and clickable straight into that day's
/// replay. Empty squares are drawn rather than skipped: the gaps are the point as much as
/// the fills.
///
/// **A square's darkness means an amount of time, not a rank.** Five fixed steps — anything,
/// half an hour, an hour and a half, three hours — so June and December are read against the
/// same ruler and a quiet month looks quiet. This port previously shaded each day against
/// the busiest day in the window, which stretched every year to fill the scale and made two
/// years indistinguishable. The thresholds are the reference's, in `ReplayCore.Heatmap`, and
/// the parity suite checks each boundary from both sides.
struct Heatmap: View {
    @Environment(\.themeTint) private var tint
    let byDay: [Int64: Int]
    let onOpenDay: (Int64) -> Void

    @State private var range: Heatmap.Kind = .year
    @State private var hovered: Int64?

    /// The reference's three, under a local name so the view's own `Heatmap` does not
    /// shadow the core type it reads its rules from.
    typealias Kind = ReplayCore.Heatmap.Range

    private var today: Int64 { startOfLocalDay(Int64(Date().timeIntervalSince1970 * 1000)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            HStack(spacing: Design.Space.card) {
                Picker("Range", selection: $range) {
                    ForEach(Kind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: Design.Space.inline)
                legend
            }

            switch range {
            case .year: yearGrid
            case .month: monthGrid
            case .week: weekRow
            }

            caption
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Activity by day. \(byDay.values.filter { $0 > 0 }.count) days recorded."
        )
    }

    /// Less → More, drawn from the same function the squares are, so it cannot describe a
    /// scale the grid is not using.
    private var legend: some View {
        HStack(spacing: Design.Space.snug) {
            Text("Less").font(Design.Text.micro).foregroundStyle(.tertiary)
            ForEach(ReplayCore.Heatmap.Level.allCases, id: \.rawValue) { level in
                RoundedRectangle(cornerRadius: Design.Radius.hair, style: .continuous)
                    .fill(colour(for: level))
                    .frame(
                        width: Design.Layout.heatmapSquare, height: Design.Layout.heatmapSquare
                    )
            }
            Text("More").font(Design.Text.micro).foregroundStyle(.tertiary)
        }
        .accessibilityHidden(true)
    }

    private var caption: some View {
        HStack(spacing: Design.Space.snug) {
            if let hovered, let seconds = byDay[hovered], seconds > 0 {
                Text("\(fullDayLabel(hovered)) · \(formatDurationShort(seconds))")
                    .font(Design.Text.micro)
                    .foregroundStyle(.secondary)
            } else {
                Text("Darker is busier. Click a day to replay it.")
                    .font(Design.Text.micro)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - The three grids

    /// Fifty-three week-columns, months labelled along the top and alternate weekdays down
    /// the side. Starts on a Sunday so every column is a real week rather than a rolling
    /// seven days, which is what makes the weekday labels mean anything.
    private var yearGrid: some View {
        let weeks = yearWeeks
        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Design.Space.tight) {
                HStack(spacing: Design.Layout.heatmapGap) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                        Text(monthLabel(startingWeek: week, at: index, in: weeks) ?? "")
                            .font(Design.Text.micro)
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                            .frame(width: Design.Layout.heatmapSquare, alignment: .leading)
                    }
                }
                // The weekday column *and* the gap after it, or every month label sits one
                // gap left of the column it names.
                .padding(.leading, Design.Layout.heatmapWeekdayColumn + Design.Layout.heatmapGap)

                HStack(alignment: .top, spacing: Design.Layout.heatmapGap) {
                    VStack(spacing: Design.Layout.heatmapGap) {
                        ForEach(0..<7, id: \.self) { index in
                            // Every other one, because seven stacked single letters at this
                            // size is a smear rather than a label.
                            Text(index % 2 == 1 ? weekdayInitials[index] : " ")
                                .font(Design.Text.micro)
                                .foregroundStyle(.tertiary)
                                .frame(
                                    width: Design.Layout.heatmapWeekdayColumn,
                                    height: Design.Layout.heatmapSquare,
                                    alignment: .leading
                                )
                        }
                    }
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: Design.Layout.heatmapGap) {
                            ForEach(week, id: \.self) { day in
                                square(day, side: Design.Layout.heatmapSquare)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, Design.Space.tight)
        }
        // Reads from its start, as the reference's does. Anchoring to the trailing edge
        // showed today first, which sounds better and was not: on any window narrow enough
        // to scroll it silently pushed the weekday labels and the first weeks off the left,
        // so the grid appeared to begin in September and had no key.
    }

    /// This month, as a calendar with the dates on. Six rows always, so paging between a
    /// 28-day February and a 31-day March does not reflow the page under the cursor.
    private var monthGrid: some View {
        let calendar = Calendar.current
        let month = calendar.dateComponents([.year, .month], from: Date(timeIntervalSince1970: Double(today) / 1000))
        let first = calendar.date(from: month) ?? Date()
        let start = weekStart(startOfLocalDay(Int64(first.timeIntervalSince1970 * 1000)))
        let cells = (0..<ReplayCore.Heatmap.monthCells).map { startOfLocalDay(start + Int64($0) * dayMillis) }
        let columns = Array(
            repeating: GridItem(.fixed(Design.Layout.heatmapMonthCell), spacing: Design.Space.snug),
            count: 7
        )
        return LazyVGrid(columns: columns, spacing: Design.Space.snug) {
            ForEach(0..<7, id: \.self) { index in
                Text(weekdayInitials[index])
                    .font(Design.Text.micro)
                    .foregroundStyle(.tertiary)
            }
            ForEach(cells, id: \.self) { day in
                let inMonth = calendar.component(.month, from: date(day))
                    == calendar.component(.month, from: date(today))
                square(day, side: Design.Layout.heatmapMonthCell) {
                    Text("\(calendar.component(.day, from: date(day)))")
                        .font(Design.Text.detail)
                        .monospacedDigit()
                        .foregroundStyle(inkOn(day))
                }
                // A day from a neighbouring month is context, not content.
                .opacity(inMonth ? 1 : Design.Colour.outOfMonth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The last seven days, large enough to carry the figure itself — at this size a shade
    /// is a decoration and the number is the information.
    private var weekRow: some View {
        let days = (0...ReplayCore.Heatmap.Range.week.backDays).map {
            startOfLocalDay(today - Int64(ReplayCore.Heatmap.Range.week.backDays - $0) * dayMillis)
        }
        return HStack(spacing: Design.Space.snug) {
            ForEach(days, id: \.self) { day in
                square(day, side: Design.Layout.heatmapWeekCell) {
                    VStack(spacing: Design.Space.hairline) {
                        Text(weekdayShort(day))
                            .font(Design.Text.micro)
                            .foregroundStyle(inkOn(day).opacity(Design.Colour.heatCaption))
                        Text(
                            (byDay[day] ?? 0) > 0
                                ? formatDurationShort(byDay[day] ?? 0) : "—"
                        )
                        .font(Design.Text.detailStrong)
                        .monospacedDigit()
                        .foregroundStyle(inkOn(day))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - One square

    private func square(_ day: Int64, side: CGFloat) -> some View {
        square(day, side: side) { EmptyView() }
    }

    private func square<Content: View>(
        _ day: Int64, side: CGFloat, @ViewBuilder content: () -> Content
    ) -> some View {
        let seconds = byDay[day] ?? 0
        let future = day > today
        return RoundedRectangle(cornerRadius: Design.Radius.hair, style: .continuous)
            .fill(future ? AnyShapeStyle(.clear) : colour(for: ReplayCore.Heatmap.level(seconds)))
            .frame(width: side, height: side)
            .overlay(content())
            .overlay {
                // Today gets a ring rather than a caption: the grid should say where you are
                // without spending a line of text on it.
                if day == today {
                    RoundedRectangle(cornerRadius: Design.Radius.hair, style: .continuous)
                        .strokeBorder(tint, lineWidth: Design.Layout.heatmapTodayRing)
                }
            }
            .onHover { hovered = $0 ? day : nil }
            .onTapGesture { if seconds > 0 { onOpenDay(day) } }
            .accessibilityElement()
            .accessibilityLabel(
                seconds > 0
                    ? "\(fullDayLabel(day)), \(formatDurationShort(seconds))"
                    : "\(fullDayLabel(day)), nothing recorded"
            )
            .accessibilityAddTraits(seconds > 0 ? .isButton : [])
    }

    /// The accent at the level's own share, over the empty-square colour. The reference
    /// mixes the two with `color-mix`; laying the accent over the same fill at the same
    /// fraction arrives at the same place, and keeps one source for what a level is worth.
    private func colour(for level: ReplayCore.Heatmap.Level) -> AnyShapeStyle {
        guard level != .none else { return AnyShapeStyle(Design.Colour.fill) }
        return AnyShapeStyle(tint.opacity(ReplayCore.Heatmap.mix(level)))
    }

    /// White on a dark square, the usual tertiary on a pale one — the same rule the
    /// reference uses, at the same level.
    private func inkOn(_ day: Int64) -> Color {
        ReplayCore.Heatmap.level(byDay[day] ?? 0).rawValue >= 3 ? .white : Color.secondary
    }

    // MARK: - Dates

    private func date(_ millis: Int64) -> Date { Date(timeIntervalSince1970: Double(millis) / 1000) }

    /// Whole weeks back from today, aligned to the week's own first day so the rows are
    /// weekdays rather than an arbitrary seven-day slice.
    private var yearWeeks: [[Int64]] {
        let gridStart = weekStart(startOfLocalDay(today - Int64(Kind.year.backDays) * dayMillis))
        return (0..<ReplayCore.Heatmap.yearWeeks).map { week in
            (0..<7).map { startOfLocalDay(gridStart + Int64(week * 7 + $0) * dayMillis) }
        }
    }

    /// A month is labelled above the column it *begins* in — and only if it begins early
    /// enough in that week to own it, or a month starting on a Saturday would label a column
    /// that is almost entirely the month before.
    private func monthLabel(startingWeek week: [Int64], at index: Int, in weeks: [[Int64]]) -> String? {
        let calendar = Calendar.current
        guard let first = week.first else { return nil }
        let month = calendar.component(.month, from: date(first))
        guard calendar.component(.day, from: date(first)) <= ReplayCore.Heatmap.monthLabelMaxDate
        else { return nil }
        if index > 0, let previous = weeks[index - 1].first,
           calendar.component(.month, from: date(previous)) == month { return nil }
        return calendar.shortMonthSymbols[month - 1]
    }

    /// The first day of the week `day` falls in, in the locale's own terms.
    ///
    /// Not "back up to Sunday", which is what both grids did first: the labels above them
    /// already followed `firstWeekday`, so on a Monday-first locale the header read
    /// M T W T F S S over a Sunday-aligned grid and every column named the wrong day.
    private func weekStart(_ day: Int64) -> Int64 {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date(day))
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return startOfLocalDay(day - Int64(offset) * dayMillis)
    }

    /// The locale's own weekday initials, in the locale's own order — not a hard-coded
    /// S M T W T F S, which is only right in English and only in a Sunday-first week.
    private var weekdayInitials: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let firstIndex = calendar.firstWeekday - 1
        return (0..<7).map { symbols[($0 + firstIndex) % 7] }
    }

    private func weekdayShort(_ day: Int64) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date(day))
    }
}
