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


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.section) {
                if collections.opened != nil {
                    Button { collections.opened = nil } label: {
                        Label(Loc.t("All collections"), systemImage: "chevron.left")
                    }
                    .buttonStyle(.link)
                    .settlesIn(0)
                }

                if let opened = collections.opened {
                    openedCollection(opened).settlesIn(1)
                } else if collections.collections.isEmpty {
                    empty.centredInPage()
                } else {
                    VStack(spacing: Design.Space.row) {
                        // Each row on its own beat; the stagger used to sit on the stack, so
                        // seven collections arrived together where upstream deals them out.
                        ForEach(Array(collections.collections.enumerated()), id: \.element.category) {
                            index, collection in
                            CollectionRow(collection: collection) {
                                collections.opened = collection.category
                            }
                            .settlesIn(index + 1)
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

    /// One collection's history: what it comes to, then every session of that kind under
    /// the day it happened on.
    ///
    /// Grouped by day rather than dated per card. Each card used to carry its own date, so a
    /// Tuesday with eight development sessions printed Tuesday eight times — the date stopped
    /// being information and became noise between the cards.
    @ViewBuilder
    private func openedCollection(_ category: SessionCategory) -> some View {
        let inCategory = collections.sessions(in: category)
        let days = Dictionary(grouping: inCategory) { startOfLocalDay($0.startedAt) }
        let ordered = days.keys.sorted(by: >)

        HStack(spacing: Design.Space.block) {
            summary(
                "\(inCategory.count)",
                inCategory.count == 1 ? "session" : "sessions"
            )
            summary(
                formatDurationShort(inCategory.reduce(0) { $0 + $1.activeSeconds }),
                "in total"
            )
            summary(
                "\(ordered.count)",
                ordered.count == 1 ? "day" : "days"
            )
            Spacer(minLength: 0)
        }

        VStack(alignment: .leading, spacing: Design.Space.block) {
            ForEach(ordered, id: \.self) { day in
                VStack(alignment: .leading, spacing: Design.Space.row) {
                    Text(fullDayLabel(day)).sectionLabelStyle()
                    VStack(spacing: Design.Space.row) {
                        ForEach(days[day] ?? [], id: \.startedAt) { session in
                            SessionCard(
                                session: session,
                                annotations: annotations,
                                export: export,
                                onDelete: { onDeleteSession(session) }
                            )
                        }
                    }
                }
            }
        }
    }

    /// One figure and what it counts, which is the shape every other summary in the app uses.
    private func summary(_ figure: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.hairline) {
            Text(figure)
                .font(Design.Text.figure)
                .monospacedDigit()
            Text(Loc.t(label))
                .font(Design.Text.micro)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(Loc.t("Nothing collected yet"), systemImage: "square.stack")
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

                VStack(alignment: .leading, spacing: Design.Space.tight) {
                    Text(collection.label).font(Design.Text.itemTitle)
                    // The apps that defined it, which says more about a collection than its
                    // name does — and as icons, the way Projects already showed them and
                    // the way upstream shows them here. Names alone made two collections of
                    // the same size indistinguishable at a glance.
                    HStack(spacing: Design.Space.snug) {
                        ForEach(collection.apps, id: \.applicationName) { app in
                            AppIcon(
                                bundleID: nil,
                                appPath: app.appPath,
                                size: Design.Icon.listItem
                            )
                        }
                        Text(collection.apps.map(\.applicationName).joined(separator: ", "))
                            .font(Design.Text.micro)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.leading, Design.Space.tight)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatDurationShort(collection.totalSeconds))
                        .font(Design.Text.figure)
                        .monospacedDigit()
                    Text(Loc.count(collection.sessionCount, "%@ session", "%@ sessions"))
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
        .buttonStyle(.row)
        .card(border: Design.Colour.fillStrong)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(collection.label), \(formatDurationShort(collection.totalSeconds)) across "
                + "\(collection.sessionCount) "
                + "\(collection.sessionCount == 1 ? "session" : "sessions")"
        )
        .accessibilityHint(Loc.t("Opens this collection"))
    }
}

#if DEBUG
#Preview("Collections") {
    let world = PreviewWorld().load()
    return CollectionsView(
        collections: world.collections, annotations: world.annotations,
        export: world.export, onDeleteSession: { _ in }
    )
    .frame(width: Design.Layout.windowWidth, height: Design.Layout.windowHeight)
}
#endif
