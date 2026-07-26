import Observation
import ReplayCore
import SwiftUI

/// Where the window is, and how it got there.
///
/// Held outside the view because the menu bar drives it too — "Open Today" has to reach a
/// window that already exists, and a `View` is a value the delegate cannot call into.
///
/// The opened day lives in a `NavigationPath` rather than an optional, so going back is the
/// system's own back: ⌘[ works, the swipe works, the title bar draws the button, and none of
/// that had to be written.
@MainActor
@Observable
final class Navigation {
    enum Surface: String, CaseIterable, Identifiable, Hashable {
        case today = "Today", timeline = "Timeline", search = "Search"
        case memories = "Memories", collections = "Collections"

        var id: String { rawValue }

        /// The glyph that names it in the sidebar. Chosen to say what the surface *is*
        /// rather than to decorate: a clock that has run backwards, a list of days, a
        /// magnifier, a memory, a set.
        var symbol: String {
            switch self {
            case .today: "sun.max"
            case .timeline: "calendar.day.timeline.left"
            case .search: "magnifyingglass"
            case .memories: "clock.arrow.circlepath"
            case .collections: "square.stack"
            }
        }

        /// What the surface answers, for the sidebar's accessibility description. A
        /// VoiceOver user hears the question, not just the noun.
        var purpose: String {
            switch self {
            case .today: "What today has been so far"
            case .timeline: "Your recent days, newest first"
            case .search: "Find a session by name, note, tag or app"
            case .memories: "What you were doing on this date before"
            case .collections: "Sessions gathered by the kind of work"
            }
        }
    }

    var surface: Surface = .today
    /// Days pushed over the current surface. A path rather than a flag, so the stack is the
    /// system's and the history is real.
    var path = NavigationPath()

    func show(_ surface: Surface) {
        path = NavigationPath()
        self.surface = surface
    }

    func open(day: Int64) { path.append(day) }

    /// Bumped when something asks for the search field.
    ///
    /// `.searchable` binds ⌘F for itself in a SwiftUI scene, but this window is an
    /// `NSWindow` hosting a view — there is no Find menu item unless the app makes one, and
    /// without it ⌘F reached nothing. A counter rather than a `Bool` so asking twice in a
    /// row still works.
    private(set) var focusSearchRequests = 0

    func focusSearch() {
        show(.search)
        focusSearchRequests += 1
    }
}

/// The window.
///
/// A `NavigationSplitView`, which is what a Mac app with five surfaces is. The previous
/// segmented control in a stack worked and read as a web page: no sidebar to collapse, no
/// toolbar to put anything in, a hand-written back button, and no way for the system to
/// restore where you were. All of that comes free here.
struct RootView: View {
    let model: AppModel
    let history: HistoryModel
    @Bindable var navigation: Navigation
    let preferences: Preferences
    let export: ExportModel
    let search: SearchModel
    let memories: MemoriesModel
    let collections: CollectionsModel

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            NavigationStack(path: $navigation.path) {
                surface
                    .navigationDestination(for: Int64.self) { dayStart in
                        DayScreen(
                            dayStart: dayStart,
                            history: history,
                            annotations: model.annotations,
                            export: export
                        )
                    }
            }
        }
        .onChange(of: navigation.surface, initial: true) { _, new in
            // Each surface reads the store directly rather than following the tracker, so
            // it reloads when shown — a session deleted elsewhere should not linger as a
            // row that opens onto nothing.
            switch new {
            case .timeline: history.reload()
            case .search: search.load()
            case .memories: memories.load()
            case .collections: collections.load()
            case .today: break
            }
        }
        .preferredColorScheme(preferences.appearance.colorScheme)
    }

    private var sidebar: some View {
        List(Navigation.Surface.allCases, selection: $navigation.surface) { item in
            NavigationLink(value: item) {
                Label(item.rawValue, systemImage: item.symbol)
            }
            .accessibilityHint(item.purpose)
        }
        .navigationSplitViewColumnWidth(
            min: Design.Layout.sidebarMinWidth,
            ideal: Design.Layout.sidebarWidth,
            max: Design.Layout.sidebarMaxWidth
        )
        .navigationTitle("Replay")
    }

    @ViewBuilder
    private var surface: some View {
        switch navigation.surface {
        case .today:
            TodayView(
                model: model, annotations: model.annotations,
                export: export, memories: memories, preferences: preferences,
                onOpenDay: { navigation.open(day: $0) }
            )
        case .timeline:
            TimelineView(
                history: history,
                annotations: model.annotations,
                export: export,
                onOpenDay: { navigation.open(day: $0) }
            )
        case .search:
            SearchView(
                search: search,
                navigation: navigation,
                annotations: model.annotations,
                export: export,
                onDeleteSession: { history.deleteSession($0); search.load() }
            )
        case .memories:
            MemoriesView(
                memories: memories,
                onOpenDay: { navigation.open(day: $0) }
            )
        case .collections:
            CollectionsView(
                collections: collections,
                annotations: model.annotations,
                export: export,
                onDeleteSession: { history.deleteSession($0); collections.load() }
            )
        }
    }
}

/// A day, as a destination on the stack.
///
/// Derived here rather than by the caller so the navigation path can hold a plain day — a
/// `NavigationPath` restores from a value, not from a struct that took a database to build.
/// That is what makes state restoration possible later without reshaping this.
private struct DayScreen: View {
    let dayStart: Int64
    let history: HistoryModel
    let annotations: AnnotationsModel
    let export: ExportModel

    @State private var day: TimelineDay?
    @State private var headline: DailySummary?
    @State private var reflection: Reflection?

    var body: some View {
        Group {
            if let day, let reflection {
                DayView(
                    day: day,
                    headline: headline,
                    reflection: reflection,
                    annotations: annotations,
                    export: export,
                    onReflect: { text in
                        history.setReflection(dayStart, text)
                        load()
                    },
                    onDeleteSession: { history.deleteSession($0); load() }
                )
            } else {
                // Never seen in practice — the load is synchronous — but a destination has
                // to have something to be before it has been loaded.
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Loaded in a task rather than in `body`: deriving a day loads its annotations, and
        // a view body must not be what mutates them.
        .task(id: dayStart) { load() }
    }

    private func load() {
        day = history.day(dayStart)
        headline = history.headline(dayStart)
        reflection = history.reflection(dayStart)
    }
}
