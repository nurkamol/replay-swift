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

    /// How far back the query looks. A narrowing of the same search, not a different one.
    var span: Search.Span = .all {
        didSet { if span != oldValue { refilter() } }
    }

    private(set) var sessions: [ActivitySession] = []
    private(set) var apps: [Search.AppHit] = []
    private(set) var collections: [Collections.Collection] = []
    private(set) var projects: [Project] = []
    private(set) var reflections: [Reflection] = []
    private(set) var concept: Search.Concept?
    /// The day a date-like query points at — "yesterday", "last friday", "one year ago".
    private(set) var jumpDay: Int64?
    /// Every bookmarked session in the window, shown when nothing has been typed.
    private(set) var bookmarked: [ActivitySession] = []
    private(set) var loaded = false

    /// The application chosen from the results, which narrows to exactly it.
    var chosenApp: String? {
        didSet { if chosenApp != oldValue { refilter() } }
    }

    /// True when the query found nothing anywhere — the one state that says so out loud.
    var foundNothing: Bool {
        !trimmedQuery.isEmpty && jumpDay == nil && concept == nil
            && collections.isEmpty && projects.isEmpty && apps.isEmpty
            && reflections.isEmpty && sessions.isEmpty
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var all: [ActivitySession] = []
    private var allProjects: [Project] = []
    private var allReflections: [Reflection] = []
    private var annotations: [Int64: SessionAnnotation] = [:]
    private let model: AppModel
    private let preferences: Preferences

    init(model: AppModel, preferences: Preferences) {
        self.model = model
        self.preferences = preferences
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
            allReflections = try model.store.reflections(from: from, to: to)
                .filter { !$0.isEmpty }
            allProjects = detectProjects(all)
            loaded = true
            refilter()
        } catch {
            all = []
            allProjects = []
            allReflections = []
            annotations = [:]
            loaded = true
        }
    }

    private func refilter() {
        let trimmed = trimmedQuery
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let from = span.start(now: now)
        let inSpan = all.filter { $0.startedAt >= from }

        bookmarked = all.filter { annotations[$0.startedAt]?.bookmarked == true }

        if let chosenApp {
            sessions = inSpan.filter { Search.usesApp(session: $0, applicationName: chosenApp) }
            clearGroups()
            return
        }

        guard !trimmed.isEmpty else {
            sessions = []
            clearGroups()
            return
        }

        jumpDay = Memories.day(matching: trimmed, now: now)

        // A concept answers instead of the literal match, not alongside it: showing both
        // "Morning work" and every session with "morning" in its name is two answers to one
        // question.
        if let found = Search.concept(for: trimmed, sessions: inSpan, annotations: annotations) {
            concept = found
            sessions = found.sessions
            apps = []
            collections = []
            projects = []
            reflections = []
            return
        }

        concept = nil
        sessions = inSpan.filter {
            Search.matches(session: $0, annotation: annotations[$0.startedAt], query: trimmed)
        }
        apps = Search.apps(matching: trimmed, in: inSpan)
        collections = Collections.compute(inSpan).filter {
            matches($0.label) || matches($0.category.rawValue)
        }
        // Projects match on their own name and kind, never on their member apps: an app
        // search belongs in the Apps group, not dragged in behind every project it touches.
        projects = allProjects.filter {
            matches(resolveProjectName($0, names: preferences.projectNames))
                || matches($0.category.rawValue)
        }
        reflections = allReflections
            .filter { $0.dayStart >= from && matches($0.text) }
            .sorted { $0.dayStart > $1.dayStart }
    }

    private func matches(_ text: String) -> Bool {
        Search.firstMatch(of: trimmedQuery, in: text) != nil
    }

    private func clearGroups() {
        apps = []
        collections = []
        projects = []
        reflections = []
        concept = nil
        jumpDay = nil
    }

    func annotation(for sessionStart: Int64) -> SessionAnnotation? { annotations[sessionStart] }
}

/// Search: find a session again by what it was called, what you wrote on it, or what you
/// were in.
struct SearchView: View {
    let search: SearchModel
    let navigation: Navigation
    @Bindable var preferences: Preferences
    let annotations: AnnotationsModel
    let export: ExportModel
    let onDeleteSession: (ActivitySession) -> Void
    let onOpenCollection: (SessionCategory) -> Void

    @FocusState private var fieldFocused: Bool

    private var typing: Bool { !search.trimmedQuery.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.section) {
                field
                if typing { refinements }

                if let chosen = search.chosenApp {
                    narrowedTo(chosen)
                }
                if let day = search.jumpDay { jumpTo(day) }

                if search.chosenApp != nil || typing {
                    if search.foundNothing { nothing.centredInPage() } else { results }
                } else if !preferences.savedSearches.isEmpty || !search.bookmarked.isEmpty {
                    recall
                } else {
                    hint.centredInPage()
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle(Loc.t("Search"))
        .onAppear { if !search.loaded { search.load() } }
        .onChange(of: navigation.focusSearchRequests, initial: true) { _, _ in
            if navigation.focusSearchRequests > 0 { fieldFocused = true }
        }
    }

    /// How far back to look, and whether to keep this query.
    ///
    /// Only while something is typed: a span control over an empty field narrows nothing,
    /// and a Save button with nothing to save is a control that cannot be used.
    private var refinements: some View {
        HStack(spacing: Design.Space.card) {
            Picker(Loc.t("How far back"), selection: Binding(
                get: { search.span }, set: { search.span = $0 }
            )) {
                ForEach(Search.Span.allCases) { span in
                    Text(span.label).tag(span)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: Design.Layout.segmentedWidth)

            Spacer(minLength: Design.Space.inline)

            let saved = preferences.isSaved(search.trimmedQuery)
            Button {
                preferences.toggleSavedSearch(search.trimmedQuery)
            } label: {
                Label(saved ? "Saved" : "Save", systemImage: saved ? "star.fill" : "star")
                    .font(Design.Text.detail.weight(.medium))
                    .foregroundStyle(saved ? AnyShapeStyle(Design.Colour.marked) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, Design.Pill.leadingRoomy)
                    .padding(.vertical, Design.Pill.countVertical)
                    .background(
                        saved
                            ? AnyShapeStyle(Design.Colour.marked.opacity(Design.Colour.streakOpacity))
                            : Design.Colour.surfaceQuiet,
                        in: Capsule()
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(saved ? "Forget this search" : "Keep this search")
            .accessibilityLabel(saved ? "Forget this search" : "Save this search")
        }
    }

    /// A query that reads like a date opens that day instead of matching nothing.
    private func jumpTo(_ dayStart: Int64) -> some View {
        Button {
            navigation.open(day: dayStart)
        } label: {
            HStack(spacing: Design.Space.row) {
                Image(systemName: "calendar.badge.clock")
                    .font(Design.Text.prose)
                    .foregroundStyle(.tint)
                    .frame(width: Design.Icon.listItem)
                VStack(alignment: .leading, spacing: Design.Space.hairline) {
                    Text(Loc.t("Jump to")).cardLabelStyle()
                    Text(fullDayLabel(dayStart)).font(Design.Text.itemTitle)
                }
                Spacer(minLength: Design.Space.inline)
                Image(systemName: "chevron.right")
                    .font(Design.Text.micro)
                    .foregroundStyle(.quaternary)
            }
            .padding(Design.Space.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.row)
        .background(Design.Colour.surfaceQuiet, in: RoundedRectangle(
            cornerRadius: Design.Radius.control, style: .continuous
        ))
    }

    /// What an empty field offers instead of a blank page: the searches you kept, and the
    /// sessions you marked. Both are things you already said were worth coming back to.
    private var recall: some View {
        VStack(alignment: .leading, spacing: Design.Space.section) {
            if !preferences.savedSearches.isEmpty {
                VStack(alignment: .leading, spacing: Design.Space.snug) {
                    SectionLabel("Saved searches")
                    FlowRow(spacing: Design.Space.snug) {
                        ForEach(preferences.savedSearches, id: \.self) { saved in
                            savedChip(saved)
                        }
                    }
                }
                .settlesIn(0)
            }
            if !search.bookmarked.isEmpty {
                VStack(alignment: .leading, spacing: Design.Space.snug) {
                    SectionLabel("Bookmarks")
                    VStack(spacing: Design.Space.row) {
                        ForEach(search.bookmarked, id: \.startedAt) { session in
                            SessionCard(
                                session: session,
                                annotations: annotations,
                                export: export,
                                onDelete: { onDeleteSession(session) }
                            )
                        }
                    }
                }
                .settlesIn(1)
            }
        }
    }

    private func savedChip(_ saved: String) -> some View {
        HStack(spacing: Design.Space.hairline) {
            Button { search.query = saved } label: {
                Text(saved).font(Design.Text.detail.weight(.medium))
            }
            .buttonStyle(.plain)
            .help(String(format: Loc.t("Search for %@ again"), "\(saved)"))
            Button { preferences.toggleSavedSearch(saved) } label: {
                Image(systemName: "xmark").font(Design.Text.pillGlyph)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .accessibilityLabel(String(format: Loc.t("Forget the saved search %@"), "\(saved)"))
        }
        .padding(.horizontal, Design.Pill.leadingRoomy)
        .padding(.vertical, Design.Pill.countVertical)
        .background(Design.Colour.surfaceQuiet, in: Capsule())
        .overlay(Capsule().strokeBorder(Design.Colour.borderQuiet))
    }

    private var nothing: some View {
        ContentUnavailableView {
            Label(
                // The quotation marks are inside the key, because which marks a language
                // uses is part of translating it — German nests them low-then-high, French
                // sets guillemets with spaces.
                String(format: Loc.t("No results for \u{201C}%@\u{201D}"), search.trimmedQuery),
                systemImage: "magnifyingglass"
            )
        } description: {
            Text(
                "Try an app name, a collection, a word from a note or reflection, a #tag — "
                    + "or a phrase like \u{201C}morning work\u{201D}, \u{201C}longest "
                    + "session\u{201D}, or \u{201C}bookmarks\u{201D}."
            )
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

            // `Loc.t`, not a bare literal: SwiftUI takes a literal as a `LocalizedStringKey`
            // and looks it up in `Bundle.main`, where this catalogue is not — so the one
            // field on this surface stayed English in every language.
            TextField(
                Loc.t("A session, a note, a tag, an app"),
                text: Binding(get: { search.query }, set: { search.query = $0 })
            )
            .textFieldStyle(.plain)
            .font(.title3)
            .focused($fieldFocused)
            // A placeholder is not a label. VoiceOver announced this as a bare "text field",
            // on the surface whose whole purpose is typing into it — found by walking the
            // accessibility tree rather than by reading the code.
            .accessibilityLabel(Loc.t("Search"))
            .accessibilityHint(Loc.t("A session, a note, a tag, an app"))
            // Escape gives the field up rather than clearing the app's state, which is
            // what Escape means everywhere else on the Mac.
            .onExitCommand { fieldFocused = false }
            .onSubmit { fieldFocused = false }

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
                .accessibilityLabel(Loc.t("Clear search"))
            }
        }
        .padding(.horizontal, Design.Space.cardRoomy)
        .frame(height: Design.Layout.searchFieldHeight)
        .card(radius: Design.Radius.control, background: Design.Colour.surfaceInset)
    }

    /// The chip that says the results are narrowed to one app, and how to stop.
    private func narrowedTo(_ app: String) -> some View {
        HStack(spacing: Design.Space.snug) {
            Text(String(format: Loc.t("in %@"), "\(app)")).font(Design.Text.detail.weight(.medium))
            Button {
                search.chosenApp = nil
            } label: {
                Image(systemName: "xmark").font(Design.Text.pillGlyph)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(format: Loc.t("Stop narrowing to %@"), "\(app)"))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, Design.Pill.leadingRoomy)
        .padding(.vertical, Design.Pill.countVertical)
        .background(Design.Colour.fillStrong, in: Capsule())
    }

    private var hint: some View {
        ContentUnavailableView {
            Label(Loc.t("Search your memory"), systemImage: "magnifyingglass")
        } description: {
            Text(
                "Find an app, a session, a project, a note, a #tag, a collection, or a line "
                    + "you reflected on. A phrase like \u{201C}morning work\u{201D} or "
                    + "\u{201C}last friday\u{201D} goes straight to that slice of the last "
                    + "\(Report.fetchDays) days. Bookmark a session and it appears here."
            )
        }
    }

    @ViewBuilder
    private var results: some View {
        if let concept = search.concept {
            group(concept.label, concept.sessions.count, "session", index: 0) {
                sessionList(concept.sessions)
            }
        }

        if !search.collections.isEmpty {
            group(nil, search.collections.count, "collection", index: 1) {
                ForEach(search.collections, id: \.category) { collection in
                    resultRow(
                        glyph: "square.stack",
                        title: collection.label,
                        detail: "\(collection.sessionCount) "
                            + (collection.sessionCount == 1 ? "session" : "sessions")
                            + " · \(formatDurationShort(collection.totalSeconds))",
                        open: { onOpenCollection(collection.category) }
                    )
                }
            }
        }

        if !search.projects.isEmpty {
            group(nil, search.projects.count, "project", index: 2) {
                ForEach(search.projects, id: \.id) { project in
                    resultRow(
                        glyph: "shippingbox",
                        title: resolveProjectName(project, names: preferences.projectNames),
                        detail: "\(project.sessionCount) "
                            + (project.sessionCount == 1 ? "session" : "sessions")
                            + " · \(formatDurationShort(project.totalSeconds))",
                        open: { navigation.open(project: project.id) }
                    )
                }
            }
        }

        if !search.apps.isEmpty {
            group(nil, search.apps.count, "app", index: 3) {
                ForEach(search.apps, id: \.applicationName) { app in
                    resultRow(
                        icon: AppIcon(
                            bundleID: app.bundleIdentifier, appPath: app.appPath,
                            size: Design.Icon.listItem
                        ),
                        title: app.applicationName,
                        detail: "\(app.sessionCount) "
                            + (app.sessionCount == 1 ? "session" : "sessions")
                            + " · \(formatDurationShort(app.seconds))",
                        open: { search.chosenApp = app.applicationName }
                    )
                }
            }
        }

        if !search.reflections.isEmpty {
            group(nil, search.reflections.count, "reflection", index: 4) {
                ForEach(search.reflections, id: \.dayStart) { reflection in
                    resultRow(
                        glyph: "quote.opening",
                        title: reflection.text,
                        detail: fullDayLabel(reflection.dayStart),
                        open: { navigation.open(day: reflection.dayStart) }
                    )
                }
            }
        }

        if search.concept == nil, !search.sessions.isEmpty {
            group(nil, search.sessions.count, "session", index: 5) {
                sessionList(search.sessions)
            }
        }
    }

    /// One labelled block of results. The count is in the label rather than beside it, so a
    /// glance down the page reads as "3 apps, 12 sessions" without stopping at each heading.
    @ViewBuilder
    private func group(
        _ label: String?, _ count: Int, _ noun: String, index: Int,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.snug) {
            SectionLabel(
                label.map { "\($0) · \(count) \(count == 1 ? noun : noun + "s")" }
                    ?? "\(count) \(count == 1 ? noun : noun + "s")"
            )
            VStack(spacing: Design.Space.row) { content() }
        }
        .settlesInAsResult(index)
    }

    @ViewBuilder
    private func sessionList(_ sessions: [ActivitySession]) -> some View {
        ForEach(Array(sessions.enumerated()), id: \.element.startedAt) { index, session in
            let day = startOfLocalDay(session.startedAt)
            let previous = index > 0 ? startOfLocalDay(sessions[index - 1].startedAt) : nil
            VStack(alignment: .leading, spacing: Design.Space.tight) {
                // A result is undated in the Timeline's sense, so it says its day —
                // "which one was that" is usually the question being asked. Only when it
                // changes, though: twelve results from one afternoon under twelve copies of
                // the same date is a column of noise, not an answer.
                if day != previous {
                    Text(fullDayLabel(day))
                        .font(Design.Text.micro)
                        .foregroundStyle(.tertiary)
                        .padding(.top, index > 0 ? Design.Space.snug : 0)
                }
                SessionCard(
                    session: session,
                    annotations: annotations,
                    export: export,
                    onDelete: { onDeleteSession(session) }
                )
            }
        }
    }

    /// The shape every non-session result takes: a mark, the matched name, what there is of
    /// it, and somewhere to go.
    private func resultRow(
        glyph: String? = nil,
        icon: AppIcon? = nil,
        title: String,
        detail: String,
        open: @escaping () -> Void
    ) -> some View {
        Button(action: open) {
            HStack(spacing: Design.Space.row) {
                if let icon {
                    icon
                } else if let glyph {
                    Image(systemName: glyph)
                        .font(Design.Text.prose)
                        .foregroundStyle(.tint)
                        .frame(width: Design.Icon.listItem)
                }
                VStack(alignment: .leading, spacing: Design.Space.hairline) {
                    Text(Highlight.mark(title, matching: search.trimmedQuery))
                        .font(Design.Text.itemTitle)
                        .lineLimit(2)
                    Text(detail)
                        .font(Design.Text.micro)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                Spacer(minLength: Design.Space.inline)
                Image(systemName: "chevron.right")
                    .font(Design.Text.micro)
                    .foregroundStyle(.quaternary)
            }
            .padding(Design.Space.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.row)
        .background(Design.Colour.surfaceQuiet, in: RoundedRectangle(
            cornerRadius: Design.Radius.control, style: .continuous
        ))
    }
}

/// Marking the run a search actually matched on.
///
/// Only the *first* occurrence, which is the reference's rule and the right one: a title
/// with the query in it four times becomes a stripe rather than a pointer.
enum Highlight {
    static func mark(_ text: String, matching query: String) -> AttributedString {
        var marked = AttributedString(text)
        guard let found = Search.firstMatch(of: query, in: text),
              let lower = AttributedString.Index(found.lowerBound, within: marked),
              let upper = AttributedString.Index(found.upperBound, within: marked)
        else { return marked }
        marked[lower..<upper].backgroundColor = Design.Colour.marked
            .opacity(Design.Colour.matchOpacity)
        return marked
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
