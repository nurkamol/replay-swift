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
        case today = "Today", apps = "Apps", week = "This Week", timeline = "Timeline", search = "Search"
        case memories = "Memories", collections = "Collections", projects = "Projects"
        case story = "Story", canvas = "Canvas"

        var id: String { rawValue }

        /// The glyph that names it in the sidebar. Chosen to say what the surface *is*
        /// rather than to decorate: a clock that has run backwards, a list of days, a
        /// magnifier, a memory, a set.
        var symbol: String {
            switch self {
            case .today: "sun.max"
            case .apps: "square.grid.2x2"
            case .week: "chart.bar"
            case .timeline: "calendar.day.timeline.left"
            case .search: "magnifyingglass"
            case .memories: "clock.arrow.circlepath"
            case .collections: "square.stack"
            case .projects: "shippingbox"
            case .story: "book.closed"
            case .canvas: "sparkles"
            }
        }

        /// What the surface answers, for the sidebar's accessibility description. A
        /// VoiceOver user hears the question, not just the noun.
        var purpose: String {
            switch self {
            case .today: "What today has been so far"
            case .apps: "Where your time went, by application"
            case .week: "The last seven days, and when you were here"
            case .timeline: "Your recent days, newest first"
            case .search: "Find a session by name, note, tag or app"
            case .memories: "What you were doing on this date before"
            case .collections: "Sessions gathered by the kind of work"
            case .projects: "The applications that keep coming back together"
            case .story: "The long view — eras, rituals, and your history told back"
            case .canvas: "Your history as a landscape you can move through"
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

    func back() { if !path.isEmpty { path.removeLast() } }

    /// An application's own history, pushed over whatever surface asked for it. A distinct
    /// type from a day so the stack can tell the two destinations apart.
    struct AppHistory: Hashable { var bundleID: String }

    /// A project, by signature.
    struct ProjectTarget: Hashable { var id: String }

    /// One of the narrative surfaces behind Story.
    enum StoryTarget: Hashable {
        case autobiography, chapters, chapter(String), legacy, museum
    }

    /// Two applications, and how they are used together.
    struct Pair: Hashable { var a: String; var b: String }

    func open(app bundleID: String) { path.append(AppHistory(bundleID: bundleID)) }

    func open(project id: String) { path.append(ProjectTarget(id: id)) }

    func open(story target: StoryTarget) { path.append(target) }

    func open(pair a: String, _ b: String) { path.append(Pair(a: a, b: b)) }

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

    /// Whether the sidebar is put away. Held here rather than in the view so the View menu
    /// can flip it — ⌃⌘S is the shortcut every Mac app with a sidebar uses, and a toolbar
    /// button that is the *only* way to reach it is not keyboard accessible.
    var sidebarCollapsed = false

    func toggleSidebar() { sidebarCollapsed.toggle() }
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
    let week: WeekModel
    let apps: AppsModel
    let appHistory: AppHistoryModel
    let projects: ProjectsModel
    let story: StoryModel
    let relationships: RelationshipsModel
    let museum: MuseumModel
    let canvas: CanvasModel
    let contextual: ContextualMemoryModel
    @Bindable var palette: CommandPaletteModel
    let timelineLayers: TimelineLayersModel
    let notifications: NotificationsModel

    /// Given so the sidebar button can reach it — the automatic one only appears in some
    /// configurations, and a sidebar you cannot put away is not a sidebar.
    let onOpenSettings: () -> Void
    /// Likewise — the overlay is an `NSWindow`, which a view cannot raise on its own.
    let onOpenScreensaver: () -> Void
    let onOpenAmbient: () -> Void
    let updates: UpdateModel

    @Environment(\.motion) private var motion
    /// The day being watched, if one is: its sessions and what to call it on screen. Held
    /// here because it fills the window.
    @State private var replaying: Playback.Day?

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { navigation.sidebarCollapsed ? .detailOnly : .all },
            set: { navigation.sidebarCollapsed = ($0 == .detailOnly) }
        )
    }

    var body: some View {
        // Over everything, because the palette is a way to *leave* whatever is under it. A
        // scrim rather than a dialog: the app stays visible behind, which is what says the
        // palette is a lens on it rather than a mode you have entered.
        Group {
            // Instead of the app rather than over it. As an overlay the toolbar still drew
            // above it — "Today · Monday, July 27" and the sidebar button sitting on top of
            // a screen that has not been introduced yet, which read as the app already open
            // behind a sheet. A first run is the whole window.
            if let replaying {
                ReplayDayView(
                    sessions: replaying.sessions, label: replaying.label,
                    onClose: { self.replaying = nil }
                )
                .transition(motion.transition(.opacity))
            } else if preferences.seenWelcome {
                ZStack(alignment: .top) {
                    window
                    paletteOverlay
                }
            } else {
                WelcomeView(
                    model: model, preferences: preferences, notifications: notifications,
                    onFinish: {
                        withAnimation(motion.animation(Design.Motion.settle)) {
                            preferences.seenWelcome = true
                        }
                    }
                )
                .transition(motion.transition(.opacity))
            }
        }
        .animation(motion.animation(Design.Motion.settle), value: preferences.seenWelcome)
        .animation(motion.animation(Design.Motion.settle), value: replaying == nil)
        .animation(motion.animation(Design.Motion.palette), value: palette.open)
        // Escape closes it wherever focus happens to be — including inside the field, where
        // a `keyboardShortcut` on a button would never see the key. `nil` when it is shut,
        // so Escape still reaches whatever else wanted it.
        .onExitCommand(perform: escape)
    }

    private var escape: (() -> Void)? {
        palette.open ? { palette.open = false } : nil
    }

    private var window: some View {
        split
            .onChange(of: navigation.surface, initial: true) { _, new in
                // Each surface reads the store directly rather than following the tracker,
                // so it reloads when shown — a session deleted elsewhere should not linger
                // as a row that opens onto nothing.
                reload(new)
            }
            .preferredColorScheme(preferences.appearance.colorScheme)
            // One tint for the whole window. Every control and every `.tint` style follows
            // this; `themeTint` is the same colour for the few places that need it concrete.
            .tint(preferences.themeColour.colour)
            .environment(\.themeTint, preferences.themeColour.resolved)
            .environment(\.surfaceStyle, preferences.surfaceStyle)
    }

    /// The window itself. Split out of `body` because the two together were more than the
    /// type checker would take.
    private var split: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            sidebar
        } detail: {
            NavigationStack(path: $navigation.path) {
                chrome(surface)
                    .navigationDestination(for: Int64.self) { dayStart in
                        chrome(
                            DayScreen(
                                dayStart: dayStart,
                                history: history,
                                annotations: model.annotations,
                                export: export,
                                story: story,
                                onReplayDay: {
                                    replaying = Playback.Day(sessions: $0, label: $1)
                                },
                                onOpenChapter: { navigation.open(story: .chapter($0)) },
                                onOpenDay: { navigation.open(day: $0) }
                            )
                        )
                    }
                    .navigationDestination(for: Navigation.StoryTarget.self) { target in
                        chrome(storyDestination(target))
                    }
                    .navigationDestination(for: Navigation.ProjectTarget.self) { target in
                        chrome(
                            ProjectDetailView(
                                id: target.id,
                                projects: projects,
                                annotations: model.annotations,
                                export: export,
                                onDeleteSession: { history.deleteSession($0) },
                                onOpenApp: { navigation.open(app: $0) },
                                onOpenDay: { navigation.open(day: $0) }
                            )
                        )
                    }
                    .navigationDestination(for: Navigation.AppHistory.self) { target in
                        chrome(
                            AppHistoryView(
                                bundleID: target.bundleID,
                                history: appHistory,
                                annotations: model.annotations,
                                export: export,
                                onDeleteSession: { history.deleteSession($0) },
                                onOpenPair: { navigation.open(pair: $0, $1) }
                            )
                        )
                    }
                    .navigationDestination(for: Navigation.Pair.self) { target in
                        chrome(
                            RelationshipView(
                                keyA: target.a, keyB: target.b,
                                relationships: relationships,
                                annotations: model.annotations,
                                export: export,
                                onDeleteSession: { history.deleteSession($0) }
                            )
                        )
                    }
            }
            // A bar rather than a dialog: an update is not urgent, nothing is waiting on the
            // answer, and a modal would stop you doing whatever you opened the app to do.
            //
            // On the *detail pane*, and it took two wrong answers to get here. As an overlay
            // it sat on top of the day's headline and cut the one figure the window exists to
            // show in half. Wrapped around the split view in a `VStack` it pushed the sidebar
            // down with it, so the sidebar stopped reaching the top of the window and left a
            // dead strip under the traffic lights — the app looked broken to announce
            // something optional. A safe-area inset displaces only the pane it belongs to,
            // which is what the rest of the window's chrome already does.
            .safeAreaInset(edge: .top, spacing: 0) {
                if updates.shouldOffer, let release = updates.available {
                    UpdateBanner(release: release, updates: updates, onDismiss: updates.dismiss)
                        .transition(motion.transition(.move(edge: .top).combined(with: .opacity)))
                }
            }
            .animation(motion.animation(Design.Motion.settle), value: updates.shouldOffer)
        }
    }

    private func reload(_ surface: Navigation.Surface) {
        switch surface {
        case .timeline: history.reload()
        case .search: search.load()
        case .memories: memories.load()
        case .collections: collections.load()
        case .week: week.load()
        case .apps: apps.load()
        case .projects: projects.load()
        case .story: story.load()
        case .canvas: canvas.load()
        case .today: break
        }
    }

    @ViewBuilder
    private var paletteOverlay: some View {
        if palette.open {
            ZStack(alignment: .top) {
                Design.Colour.scrim
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                CommandPaletteView(palette: palette, onRun: run)
                    .padding(.top, Design.Layout.paletteTopInset)
            }
            // A fade and nothing else. The first version slid down from the top, and a
            // palette you open by reflex should not make you wait for it to arrive — the
            // fade is short enough to read as instant while still not being a hard cut.
            .transition(.opacity)
        }
    }

    private func close() { palette.open = false }

    /// Run what the palette was asked for, then get out of the way.
    private func run(_ action: CommandPaletteModel.Item.Action) {
        close()
        switch action {
        case .surface(let surface): navigation.show(surface)
        case .app(let bundleID): navigation.open(app: bundleID)
        case .project(let id): navigation.open(project: id)
        case .day(let day): navigation.open(day: day)
        case .screensaver: onOpenScreensaver()
        case .ambient: onOpenAmbient()
        case .settings: onOpenSettings()
        case .toggleSidebar:
            withAnimation(motion.animation(Design.Motion.settle)) { navigation.toggleSidebar() }
        }
    }

    /// One entry in the sidebar. The rows are built by hand rather than from `allCases`
    /// because the order is a grouping decision, not the order the cases happen to be
    /// declared in.
    /// One row at the foot of the sidebar, laid out to match the list above it.
    private func footerRow(
        _ title: String, _ glyph: String, help: String, trailing: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Design.Space.inline) {
                sidebarLabel(title, glyph)
                Spacer(minLength: Design.Space.tight)
                if let trailing { shortcutHint(trailing) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Design.Space.snug)
            .padding(.horizontal, Design.Layout.sidebarRowInset)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// The shape of every row in the sidebar: a glyph in a fixed column, then its name.
    ///
    /// The column is what makes the labels line up. A `Label` sizes its icon to the glyph,
    /// and SF Symbols are not one width — a magnifier is narrower than a bar chart — so
    /// without it every row began at a slightly different place.
    /// A shortcut as a menu would print it: quiet, on the far side, and read as a fact about
    /// the row rather than as part of its name.
    ///
    /// One function so a list row and a footer row print it the same way — the sidebar's two
    /// halves are laid out by different things, and this is the second time that has been a
    /// chance for them to disagree.
    private func shortcutHint(_ keys: String) -> some View {
        Text(keys)
            .font(Design.Text.micro)
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private func sidebarLabel(_ title: String, _ glyph: String, selected: Bool = false) -> some View {
        Label {
            // One line, always. A sidebar row that wraps breaks the even rhythm the column
            // is read by, and the sidebar is resizable, so any row is one drag from being
            // too narrow for its own name.
            Text(title).lineLimit(1)
        } icon: {
            Group {
                if selected {
                    // Left alone on the selected row, and that is the fix rather than the
                    // omission. The tint below is the theme colour; a selected row's
                    // background *is* the theme colour, so tinting the glyph painted it onto
                    // itself and the icon vanished — the row read as a label with a gap
                    // where its symbol should be. SwiftUI already knows what to draw on a
                    // selection, including when the window is not key and the selection is
                    // grey rather than coloured, which a hard-coded white would get wrong.
                    Image(systemName: glyph)
                } else {
                    // Tinted explicitly rather than left to the `Label`'s default: a sidebar
                    // glyph is drawn with AppKit's `controlAccentColor`, which a SwiftUI
                    // `.tint` does not reach — so with a theme colour chosen, every other
                    // control in the window followed it and the sidebar alone stayed the
                    // system blue.
                    Image(systemName: glyph).foregroundStyle(.tint)
                }
            }
            .frame(width: Design.Icon.sidebarColumn, alignment: .center)
        }
    }

    private func row(_ item: Navigation.Surface) -> some View {
        NavigationLink(value: item) {
            HStack(spacing: Design.Space.tight) {
                sidebarLabel(item.rawValue, item.symbol, selected: navigation.surface == item)
                // Every surface with a key says so, in the column the footer already uses.
                // The keyboard is the one thing an interface cannot show you by drawing it,
                // so the only way anybody learns these is being told — and Settings is a
                // long way to go to find out that Today is ⌘1.
                if let keys = Shortcuts.keys(for: item) {
                    Spacer(minLength: Design.Space.tight)
                    shortcutHint(keys.joined())
                }
            }
        }
        .accessibilityHint(item.purpose)
    }

    /// Show or hide the sidebar. Named for what it will do, not for what it is, so
    /// VoiceOver announces the action rather than the furniture.
    private var sidebarToggle: some View {
        Button {
            withAnimation(motion.animation(Design.Motion.settle)) {
                navigation.toggleSidebar()
            }
        } label: {
            Image(systemName: "sidebar.leading")
        }
        .help(navigation.sidebarCollapsed ? "Show Sidebar" : "Hide Sidebar")
        .accessibilityLabel(navigation.sidebarCollapsed ? "Show sidebar" : "Hide sidebar")
    }

    /// A node leads wherever that kind of thing lives — the canvas is a way *into* the app
    /// rather than a place of its own.
    private func openCanvasNode(_ node: CanvasGraph.Node) {
        switch node.type {
        case .app: navigation.open(app: node.ref)
        case .project: navigation.open(project: node.ref)
        case .chapter: navigation.open(story: .chapter(node.ref))
        case .collection:
            collections.opened = SessionCategory(rawValue: node.ref)
            navigation.show(.collections)
        case .moment:
            if let day = Int64(node.ref) { navigation.open(day: day) }
        }
    }

    @ViewBuilder
    private func storyDestination(_ target: Navigation.StoryTarget) -> some View {
        switch target {
        case .autobiography:
            AutobiographyView(story: story)
        case .chapters:
            ChaptersView(story: story, onOpen: { navigation.open(story: .chapter($0)) })
        case .chapter(let id):
            ChapterDetailView(
                id: id, story: story, onOpenDay: { navigation.open(day: $0) }
            )
        case .museum:
            MuseumView(
                museum: museum,
                annotations: model.annotations,
                export: export,
                onOpenDay: { navigation.open(day: $0) },
                onOpenProject: { navigation.open(project: $0) },
                onDeleteSession: { history.deleteSession($0) }
            )
        case .legacy:
            LegacyView(
                model: model, story: story, projects: projects,
                onOpenApp: { navigation.open(app: $0) },
                onOpenAutobiography: { navigation.open(story: .autobiography) },
                onOpenDay: { navigation.open(day: $0) }
            )
        }
    }

    /// The window's own controls, which have to be attached to *every* screen.
    ///
    /// A toolbar declared on the root view — or on the stack around it — vanishes the moment
    /// a destination is pushed, because the innermost view's toolbar wins and a pushed
    /// screen has none. And this window hosts SwiftUI inside an `NSWindow` rather than being
    /// a `WindowGroup`, so no automatic back button appears to replace it. The result was a
    /// pushed screen with no way out and no sidebar toggle: the only route back was clicking
    /// a sidebar item, and ⌘[ did nothing. Found by opening an application's history and
    /// looking for the way back.
    private func chrome<Content: View>(_ content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .navigation) { sidebarToggle }
            if !navigation.path.isEmpty {
                ToolbarItem(placement: .navigation) { backButton }
            }
        }
    }

    /// Back, one step.
    ///
    /// Hand-written because the automatic one does not appear in this hosting
    /// configuration. ⌘[ is bound here too — it is what every Mac app uses for back, and it
    /// was doing nothing.
    private var backButton: some View {
        Button {
            withAnimation(motion.animation(Design.Motion.settle)) {
                navigation.back()
            }
        } label: {
            Image(systemName: "chevron.backward")
        }
        .keyboardShortcut("[", modifiers: .command)
        .help(Loc.t("Back"))
        .accessibilityLabel(Loc.t("Back"))
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Grouped rather than one flat list of ten. The sections answer three different
            // questions — what is happening, what I work in, what has happened — and a Mac
            // sidebar is expected to say so rather than make you read the whole column.
            List(selection: $navigation.surface) {
                Section {
                    row(.today)
                    row(.search)
                }
                Section("Recent") {
                    row(.week)
                    row(.timeline)
                }
                Section("Library") {
                    row(.apps)
                    row(.projects)
                    row(.collections)
                }
                Section("Looking back") {
                    // Gone from the sidebar when looking back is switched off, as upstream:
                    // a surface for a thing you have asked not to see is a dead end.
                    if preferences.todayInHistory { row(.memories) }
                    row(.story)
                    row(.canvas)
                }
            }

            // The screensaver and Settings sit at the foot rather than in the list: neither
            // is a place in the app, and putting them among the surfaces would suggest they
            // are. Both are also in the menus, for anyone who reaches there first.
            //
            // Laid out by a stack rather than by the `List`, which is what put them out of
            // line: a sidebar list insets its own rows, so a footer padded to its own taste
            // sat several points to the left of everything above it. `footerRow` restores
            // the list's inset and gives the glyph the same fixed column, so one vertical
            // line runs down every icon in the sidebar and another down every label.
            Divider()
                .padding(.top, Design.Space.tight)

            // The palette is the fastest way anywhere in this app and the only one with no
            // sign of itself on screen — a shortcut you have to already know about is a
            // shortcut most people never find. So it says so, in the one place a Mac app has
            // room to, and it opens on a click as well: a hint that only hints is a hint you
            // have to act on somewhere else.
            //
            // "Commands" rather than "Command Palette": with the shortcut on the right there
            // are about 108 points left for the name at the sidebar's own width, and the
            // longer one needs more than that — it wrapped onto two lines, which is a worse
            // way to be precise than being short.
            footerRow(
                "Commands", "command",
                help: "Go anywhere, or do anything, by name",
                trailing: "⌘K"
            ) { palette.open = true }

            footerRow(
                "Ambient Mode", "rectangle.on.rectangle",
                help: "Today, large enough to read across a room", action: onOpenAmbient
            )
            footerRow(
                "Screensaver", "sparkles.tv",
                help: "A slow drift through your day", action: onOpenScreensaver
            )
            footerRow(
                // Settings sits at the foot of the sidebar rather than only in a menu: it
                // is where every app with a source list puts the thing you reach for last,
                // and it stops Settings being a shortcut you have to know about.
                "Settings", "gearshape",
                help: "Replay Settings", action: onOpenSettings
            )
            .keyboardShortcut(",", modifiers: .command)
            .padding(.bottom, Design.Space.tight)
        }
        .navigationSplitViewColumnWidth(
            min: Design.Layout.sidebarMinWidth,
            ideal: Design.Layout.sidebarWidth,
            max: Design.Layout.sidebarMaxWidth
        )
        .navigationTitle(Loc.t("Replay"))
    }

    @ViewBuilder
    private var surface: some View {
        switch navigation.surface {
        case .today:
            TodayView(
                model: model, annotations: model.annotations,
                export: export, memories: memories, contextual: contextual,
                preferences: preferences,
                onOpenDay: { navigation.open(day: $0) },
                onReplayDay: { replaying = Playback.Day(sessions: $0, label: "Today") }
            )
        case .apps:
            AppsView(
                apps: apps, preferences: preferences,
                onOpenApp: { navigation.open(app: $0) }
            )
        case .canvas:
            CanvasView(
                canvas: canvas,
                onOpen: openCanvasNode,
                onOpenDay: { navigation.open(day: $0) },
                paletteOpen: palette.open
            )
        case .story:
            StoryView(story: story, onOpen: { navigation.open(story: $0) })
        case .projects:
            ProjectsView(projects: projects, onOpen: { navigation.open(project: $0) })
        case .week:
            WeekView(week: week)
        case .timeline:
            TimelineView(
                history: history,
                overlays: timelineLayers,
                annotations: model.annotations,
                export: export,
                onOpenDay: { navigation.open(day: $0) },
                onReplayDay: { replaying = Playback.Day(sessions: $0, label: $1) }
            )
        case .search:
            SearchView(
                search: search,
                navigation: navigation,
                preferences: preferences,
                annotations: model.annotations,
                export: export,
                onDeleteSession: { history.deleteSession($0); search.load() },
                onOpenCollection: {
                    collections.opened = $0
                    navigation.show(.collections)
                }
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
    let story: StoryModel
    let onReplayDay: ([ActivitySession], String) -> Void
    let onOpenChapter: (String) -> Void
    let onOpenDay: (Int64) -> Void

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
                    onDeleteSession: { history.deleteSession($0); load() },
                    onReplayDay: onReplayDay,
                    context: context,
                    chapterName: context.map { chapter in
                        story.chapters.first { $0.id == chapter.chapter.id }?.name
                            ?? chapterDefaultName(chapter.chapter)
                    } ?? "",
                    onOpenChapter: onOpenChapter,
                    onOpenDay: onOpenDay
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

    /// Where this day sits in the long view. Read from the chapters Story already built —
    /// there is one set of them, and a second detection here could disagree with the screen
    /// the card links to.
    private var context: ChapterContext? {
        chapterContext(
            for: dayStart,
            now: Int64(Date().timeIntervalSince1970 * 1000),
            chapters: story.chapters.map(\.chapter)
        )
    }

    private func load() {
        day = history.day(dayStart)
        headline = history.headline(dayStart)
        reflection = history.reflection(dayStart)
        if !story.loaded { story.load() }
    }
}
