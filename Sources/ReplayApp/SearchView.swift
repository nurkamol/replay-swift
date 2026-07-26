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
    let annotations: AnnotationsModel
    let export: ExportModel
    let onDeleteSession: (ActivitySession) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if search.chosenApp != nil || !search.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    results
                } else {
                    hint
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .onAppear { if !search.loaded { search.load() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Search")
                .font(.system(size: 28, weight: .bold))

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                TextField("A session, a note, a tag, an app…", text: Binding(
                    get: { search.query },
                    set: { search.query = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.body)
                if !search.query.isEmpty {
                    Button {
                        search.chosenApp = nil
                        search.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))

            if let chosen = search.chosenApp {
                HStack(spacing: 6) {
                    Text("in \(chosen)").font(.caption.weight(.medium))
                    Button {
                        search.chosenApp = nil
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(.quaternary.opacity(0.5), in: Capsule())
            }
        }
    }

    private var hint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Find a session again")
                .font(.headline)
            Text(
                "Search what a session was called, the note you wrote on it, or a tag. "
                    + "Naming an app finds the time you spent in it, and a few phrases — "
                    + "\"morning\", \"longest\", \"bookmarked\" — go straight to that slice of "
                    + "the last \(Report.fetchDays) days."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 30)
    }

    @ViewBuilder
    private var results: some View {
        if let concept = search.concept {
            SectionLabel(concept.label)
        }

        if !search.apps.isEmpty {
            SectionLabel("Applications")
            VStack(spacing: 6) {
                ForEach(search.apps, id: \.applicationName) { app in
                    Button {
                        search.chosenApp = app.applicationName
                    } label: {
                        HStack(spacing: 10) {
                            AppIcon(bundleID: app.bundleIdentifier, appPath: app.appPath, size: 20)
                            Text(app.applicationName).font(.body)
                            Spacer()
                            Text("\(app.sessionCount) \(app.sessionCount == 1 ? "session" : "sessions")")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(formatDurationShort(app.seconds))
                                .font(.callout.weight(.medium))
                                .monospacedDigit()
                        }
                        .padding(10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }

        if search.sessions.isEmpty {
            Text("Nothing found in the last \(Report.fetchDays) days.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 20)
        } else {
            SectionLabel(
                "\(search.sessions.count) \(search.sessions.count == 1 ? "session" : "sessions")"
            )
            VStack(spacing: 10) {
                ForEach(search.sessions, id: \.startedAt) { session in
                    VStack(alignment: .leading, spacing: 3) {
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
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.6)
    }
}
