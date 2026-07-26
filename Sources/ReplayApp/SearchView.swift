import ReplayCore
import SwiftUI

/// Everything Search needs, filtered as you type.
///
/// The month is loaded once and filtered in memory rather than re-queried per keystroke:
/// the derivation is the expensive part, and doing it again for every letter would make the
/// field feel heavy for no gain.
@MainActor
@Observable
final class SearchModel {
    var query: String = "" {
        didSet { if query != oldValue { refilter() } }
    }

    private(set) var sessions: [ActivitySession] = []
    private(set) var apps: [Search.AppHit] = []
    private(set) var concept: Search.Concept?
    private(set) var loaded = false

    /// The application chosen from the results, which narrows to exactly it.
    var chosenApp: String? {
        didSet { if chosenApp != oldValue { refilter() } }
    }

    private var all: [ActivitySession] = []
    private var annotations: [Int64: SessionAnnotation] = [:]
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    /// Load the searchable window — the same span an export covers, so what you can find
    /// and what you can take with you are the same history.
    func load() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let todayStart = startOfLocalDay(now)
        let from = todayStart - Int64(Report.fetchDays - 1) * dayMillis
        let to = todayStart + dayMillis
        do {
            let events = try model.store.sessions(from: from, to: to)
                .filter { $0.startedAt >= from }
            all = Report.sessions(in: events, now: now)
            annotations = Dictionary(
                uniqueKeysWithValues: try model.store.annotations(from: from, to: to)
                    .map { ($0.sessionStart, $0) }
            )
            loaded = true
            refilter()
        } catch {
            all = []
            annotations = [:]
            loaded = true
        }
    }

    private func refilter() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if let chosenApp {
            sessions = all.filter { Search.usesApp(session: $0, applicationName: chosenApp) }
            apps = []
            concept = nil
            return
        }

        guard !trimmed.isEmpty else {
            sessions = []
            apps = []
            concept = nil
            return
        }

        // A concept answers instead of the literal match, not alongside it: showing both
        // "Morning work" and every session with "morning" in its name is two answers to one
        // question.
        if let found = Search.concept(for: trimmed, sessions: all, annotations: annotations) {
            concept = found
            sessions = found.sessions
            apps = []
            return
        }

        concept = nil
        sessions = all.filter {
            Search.matches(session: $0, annotation: annotations[$0.startedAt], query: trimmed)
        }
        apps = Search.apps(matching: trimmed, in: all)
    }

    func annotation(for sessionStart: Int64) -> SessionAnnotation? { annotations[sessionStart] }
}

/// Search: find a session again by what it was called, what you wrote on it, or what you
/// were in.
struct SearchView: View {
    let search: SearchModel
    let navigation: Navigation
    let annotations: AnnotationsModel
    let export: ExportModel
    let onDeleteSession: (ActivitySession) -> Void

    @Environment(\.motion) private var motion
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.section) {
                field

                if let chosen = search.chosenApp {
                    narrowedTo(chosen)
                }
                if search.chosenApp != nil || !search.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    results
                } else {
                    hint.centredInPage()
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle("Search")
        .onAppear { if !search.loaded { search.load() } }
        .onChange(of: navigation.focusSearchRequests, initial: true) { _, _ in
            if navigation.focusSearchRequests > 0 { fieldFocused = true }
        }
    }

    /// The search field, leading the surface at full width.
    ///
    /// In the toolbar it was a small box in the top right of a wide window, which reads as
    /// a filter on something rather than as the point of the screen. Searching *is* this
    /// surface, so the field is the first and widest thing on it — the shape Spotlight and
    /// Notes use when finding is the task rather than a refinement of one.
    private var field: some View {
        HStack(spacing: Design.Space.row) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.tertiary)

            TextField(
                "A session, a note, a tag, an app",
                text: Binding(get: { search.query }, set: { search.query = $0 })
            )
            .textFieldStyle(.plain)
            .font(.title3)
            .focused($fieldFocused)
            // Escape gives the field up rather than clearing the app's state, which is
            // what Escape means everywhere else on the Mac.
            .onExitCommand { fieldFocused = false }

            if !search.query.isEmpty {
                Button {
                    search.chosenApp = nil
                    search.query = ""
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Design.Space.cardRoomy)
        .frame(height: Design.Layout.searchFieldHeight)
        .card(radius: Design.Radius.control, background: Design.Colour.surfaceInset)
    }

    /// The chip that says the results are narrowed to one app, and how to stop.
    private func narrowedTo(_ app: String) -> some View {
        HStack(spacing: Design.Space.snug) {
            Text("in \(app)").font(Design.Text.detail.weight(.medium))
            Button {
                search.chosenApp = nil
            } label: {
                Image(systemName: "xmark").font(Design.Text.pillGlyph)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop narrowing to \(app)")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, Design.Pill.leadingRoomy)
        .padding(.vertical, Design.Pill.countVertical)
        .background(Design.Colour.fillStrong, in: Capsule())
    }

    private var hint: some View {
        ContentUnavailableView {
            Label("Find a session again", systemImage: "magnifyingglass")
        } description: {
            Text(
                "Search what a session was called, the note you wrote on it, or a tag. "
                    + "Naming an app finds the time you spent in it, and a few phrases — "
                    + "\"morning\", \"longest\", \"bookmarked\" — go straight to that slice "
                    + "of the last \(Report.fetchDays) days."
            )
        }
    }

    @ViewBuilder
    private var results: some View {
        if let concept = search.concept {
            SectionLabel(concept.label)
        }

        if !search.apps.isEmpty {
            SectionLabel("Applications")
            VStack(spacing: Design.Space.snug) {
                ForEach(search.apps, id: \.applicationName) { app in
                    Button {
                        search.chosenApp = app.applicationName
                    } label: {
                        HStack(spacing: Design.Space.row) {
                            AppIcon(bundleID: app.bundleIdentifier, appPath: app.appPath, size: Design.Icon.listItem)
                            Text(app.applicationName).font(.body)
                            Spacer()
                            Text("\(app.sessionCount) \(app.sessionCount == 1 ? "session" : "sessions")")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(formatDurationShort(app.seconds))
                                .font(Design.Text.figure)
                                .monospacedDigit()
                        }
                        .padding(Design.Space.row)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Design.Colour.surfaceQuiet, in: RoundedRectangle(cornerRadius: Design.Radius.control))
                }
            }
        }

        if search.sessions.isEmpty {
            ContentUnavailableView.search
        } else {
            SectionLabel(
                "\(search.sessions.count) \(search.sessions.count == 1 ? "session" : "sessions")"
            )
            VStack(spacing: Design.Space.row) {
                ForEach(search.sessions, id: \.startedAt) { session in
                    VStack(alignment: .leading, spacing: Design.Space.tight) {
                        // A result is undated in the Timeline's sense, so it says its day —
                        // "which one was that" is usually the question being asked.
                        Text(fullDayLabel(startOfLocalDay(session.startedAt)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        SessionCard(
                            session: session,
                            annotations: annotations,
                            export: export,
                            onDelete: { onDeleteSession(session) }
                        )
                    .settlesIntoView(reduced: motion.reduced)
                    }
                }
            }
        }
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Design.Text.sectionLabel)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(Design.Text.labelKerning)
    }
}
