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
        loaded = true
    }
}

/// The list of them, and a card for Today when there is one worth showing.
struct MemoriesView: View {
    let memories: MemoriesModel
    let onOpenDay: (Int64) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Memories")
                        .font(.system(size: 28, weight: .bold))
                    Text("What you were doing on this date before.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if memories.memories.isEmpty {
                    empty
                } else {
                    VStack(spacing: 10) {
                        ForEach(memories.memories, id: \.range.key) { memory in
                            MemoryRow(memory: memory, onOpen: { onOpenDay(memory.range.dayStart) })
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .onAppear { memories.load() }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing to look back on yet")
                .font(.headline)
            Text(
                "Replay looks at the same date a week, a month, and up to two years ago. "
                    + "Once you have history at one of those, it appears here — and it keeps "
                    + "appearing after the raw activity has been pruned, because a day's "
                    + "headline outlives it."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 30)
    }
}

private struct MemoryRow: View {
    let memory: Memories.Memory
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(memory.range.label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .kerning(0.6)
                        .textCase(.uppercase)
                    Text(fullDayLabel(memory.range.dayStart))
                        .font(.body.weight(.medium))
                    if let top = memory.summary.topAppName {
                        Text("Mostly \(top)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(formatDurationShort(memory.summary.activeSeconds))
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary.opacity(0.5), lineWidth: 1)
        )
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
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(memory.range.label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .kerning(0.6)
                        .textCase(.uppercase)
                    Text(detail)
                        .font(.callout)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary.opacity(0.4), lineWidth: 1)
        )
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
