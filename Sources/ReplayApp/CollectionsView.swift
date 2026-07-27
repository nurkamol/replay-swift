import ReplayCore
import SwiftUI

/// Sessions gathered by the kind of work they were.
///
/// Reads the same month every other derived surface reads, and folds it. There is nothing
/// to persist: a collection is a view of the sessions, not a thing the user maintains.
@MainActor
@Observable
final class CollectionsModel {
    private(set) var collections: [Collections.Collection] = []
    private(set) var sessions: [ActivitySession] = []
    private(set) var loaded = false

    /// The collection being read, or `nil` for the list of them.
    var opened: SessionCategory?

    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func load() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let todayStart = startOfLocalDay(now)
        let from = todayStart - Int64(Report.fetchDays - 1) * dayMillis
        let to = todayStart + dayMillis
        do {
            let events = try model.store.sessions(from: from, to: to)
                .filter { $0.startedAt >= from }
            sessions = Report.sessions(in: events, now: now)
            collections = Collections.compute(sessions)
            loaded = true
        } catch {
            sessions = []
            collections = []
            loaded = true
        }
    }

    func sessions(in category: SessionCategory) -> [ActivitySession] {
        sessions.filter { $0.category == category }
    }
}

/// One glyph per category, so a collection reads the same wherever it appears.
func collectionSymbol(_ category: SessionCategory) -> String {
    switch category {
    case .development: "chevron.left.forwardslash.chevron.right"
    case .design: "paintpalette"
    case .research: "safari"
    case .communication: "bubble.left.and.bubble.right"
    case .writing: "pencil.line"
    case .media: "music.note"
    case .admin: "wrench.and.screwdriver"
    case .other: "safari"
    }
}

struct CollectionsView: View {
    let collections: CollectionsModel
    let annotations: AnnotationsModel
    let export: ExportModel
    let onDeleteSession: (ActivitySession) -> Void

    @Environment(\.motion) private var motion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.section) {
                if let opened = collections.opened {
                    Button { collections.opened = nil } label: {
                        Label("All collections", systemImage: "chevron.left")
                    }
                    .buttonStyle(.link)
                }

                if let opened = collections.opened {
                    openedCollection(opened)
                } else if collections.collections.isEmpty {
                    empty.centredInPage()
                } else {
                    VStack(spacing: Design.Space.row) {
                        ForEach(collections.collections, id: \.category) { collection in
                            CollectionRow(collection: collection) {
                                collections.opened = collection.category
                            }
                        }
                    }
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle(
            collections.opened.map(Collections.label(for:)) ?? "Collections"
        )
        .navigationSubtitle(
            collections.opened == nil ? "Sessions gathered by the kind of work they were" : ""
        )
        .onAppear { if !collections.loaded { collections.load() } }
    }

    @ViewBuilder
    private func openedCollection(_ category: SessionCategory) -> some View {
        let inCategory = collections.sessions(in: category)
        Text("\(inCategory.count) \(inCategory.count == 1 ? "session" : "sessions")")
            .font(Design.Text.sectionLabel)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(Design.Text.labelKerning)

        VStack(spacing: Design.Space.row) {
            ForEach(inCategory, id: \.startedAt) { session in
                VStack(alignment: .leading, spacing: Design.Space.tight) {
                    Text(fullDayLabel(startOfLocalDay(session.startedAt)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    SessionCard(
                        session: session,
                        annotations: annotations,
                        export: export,
                        onDelete: { onDeleteSession(session) }
                    )
                    .settlesIn(0)
                }
            }
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("Nothing collected yet", systemImage: "square.stack")
        } description: {
            Text(
                "A collection is every session of one kind — development, research, writing. "
                    + "They appear on their own as you work, with nothing to set up and "
                    + "nothing to file."
            )
        }
    }
}

private struct CollectionRow: View {
    let collection: Collections.Collection
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Design.Space.card) {
                Image(systemName: collectionSymbol(collection.category))
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: Design.Icon.glyphColumn)

                VStack(alignment: .leading, spacing: Design.Space.hairline) {
                    Text(collection.label).font(Design.Text.itemTitle)
                    // The apps that defined it, which says more about a collection than
                    // its name does.
                    Text(collection.apps.map(\.applicationName).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatDurationShort(collection.totalSeconds))
                        .font(Design.Text.figure)
                        .monospacedDigit()
                    Text("\(collection.sessionCount) \(collection.sessionCount == 1 ? "session" : "sessions")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(Design.Space.cardRoomy)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .card(border: Design.Colour.fillStrong)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(collection.label), \(formatDurationShort(collection.totalSeconds)) across "
                + "\(collection.sessionCount) "
                + "\(collection.sessionCount == 1 ? "session" : "sessions")"
        )
        .accessibilityHint("Opens this collection")
    }
}
