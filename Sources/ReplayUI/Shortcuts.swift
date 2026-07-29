import AppKit

/// Every key Replay binds, declared once.
///
/// It used to be three lists that nothing could compare. An `NSMenu` built by hand in
/// `main.swift`, fourteen `.keyboardShortcut` calls spread across the views, and a table in
/// Settings written out to match — only the first two did anything, so the one a person
/// actually reads was the one nothing kept honest. The file itself said so: "written out
/// rather than derived … this table can drift from the truth, which is the honest cost of
/// having it".
///
/// It is derived now. The View menu is built from ``menu`` and Settings renders both lists,
/// so those two cannot disagree about a key, a modifier or a name. What this cannot do is
/// bind a shortcut that lives inside a SwiftUI view — `.keyboardShortcut` is a view modifier
/// and AppKit has no way to be told about it from here — so those are declared in
/// ``elsewhere`` and `tools/shortcut-audit.mjs` checks the claim both ways: every one named
/// here is really bound in the sources, and no view binds one this file has never heard of.
enum Shortcuts {

    /// What a shortcut does, so the catalogue can stay free of selectors — the methods that
    /// answer these live on the app delegate and stay private to it.
    enum Command: String {
        case today, palette, apps, week, timeline, search, memories
        case collections, projects, story, canvas, sidebar, screensaver, ambient, note
    }

    /// Which part of the Settings table an entry appears under.
    enum Group: String, CaseIterable {
        case around = "Getting around"
        case window = "The window"
        case canvas = "On the Canvas"
        case anywhere = "Anywhere"
    }

    /// A modifier, in the order macOS prints them.
    enum Modifier: String {
        case control = "⌃", option = "⌥", shift = "⇧", command = "⌘"

        var flag: NSEvent.ModifierFlags {
            switch self {
            case .control: .control
            case .option: .option
            case .shift: .shift
            case .command: .command
            }
        }
    }

    struct Entry {
        /// What the menu calls it. `nil` for anything not in the View menu.
        var menuTitle: String?
        /// What Settings calls it, which is sometimes shorter than the menu's wording.
        var label: String
        /// The key as macOS wants it — lowercase for letters, since the modifier says the
        /// rest. ``display`` is what a person is shown.
        var key: String
        var modifiers: [Modifier] = [.command]
        var command: Command?
        /// `nil` keeps it out of Settings — Canvas has a menu item and no shortcut, and a
        /// table of keys is no place for a row with no key in it.
        var group: Group?
        /// The sidebar row this belongs to, so the row can say what its key is. Named rather
        /// than matched on a label: both types live in this module, so the compiler checks
        /// the pairing and a renamed surface cannot silently stop showing its shortcut.
        var surface: Navigation.Surface?
        var separatorBefore = false
        /// A key bound by a SwiftUI view rather than by a menu, and the file it lives in.
        /// Checked by the audit; `nil` means a menu binds it.
        var boundInView: String?

        /// The keys as they are shown: modifiers in order, then the key itself, upper-cased
        /// when it is a letter because that is how a Mac writes a shortcut.
        var display: [String] {
            modifiers.map(\.rawValue) + [key.count == 1 ? key.uppercased() : key]
        }

        var flags: NSEvent.ModifierFlags {
            modifiers.reduce(into: NSEvent.ModifierFlags()) { $0.insert($1.flag) }
        }
    }

    /// The View menu, in the order it is built, which is the order the sidebar shows.
    ///
    /// The digits run 1–9 straight down the sidebar, and getting there meant parting from the
    /// reference's assignment. Upstream the sidebar is a flat list of ten in a different
    /// order — Today, Apps, This Week, Timeline, Canvas, Memories, Story, Collections,
    /// Projects, Search — and its keys are near-positional in *that* arrangement. This port
    /// groups the ten into three sections instead, which is its own decision and a good one,
    /// but it had kept the reference's numbers: ⌘5 sat on Search at the second row and ⌘2 on
    /// Apps at the fifth, so the column read 1, 5, 3, 4, 2, 8, 7, 6, 9 top to bottom.
    ///
    /// A shortcut column nobody can predict is worse than one nobody can see. The separators
    /// mirror the sidebar's own sections, so the menu reads the way the sidebar does.
    static let menu: [Entry] = [
        Entry(
            menuTitle: "Hide Sidebar", label: "Show or hide the sidebar", key: "s",
            modifiers: [.control, .command], command: .sidebar, group: .window
        ),
        Entry(
            menuTitle: "Today", label: "Today", key: "1",
            command: .today, group: .around, surface: .today, separatorBefore: true
        ),
        Entry(
            menuTitle: "Go to Anything…", label: "Go to anything", key: "k",
            command: .palette, group: .around
        ),
        // Search is ⌘2 rather than ⌘F: ⌘F is Find, and `.searchable` binds it to focus the
        // field — a menu item that stole it switched surfaces and then swallowed the
        // keystrokes meant for the search box.
        Entry(
            menuTitle: "Search", label: "Search", key: "2",
            command: .search, group: .around, surface: .search
        ),
        Entry(
            menuTitle: "This Week", label: "This Week", key: "3",
            command: .week, group: .around, surface: .week, separatorBefore: true
        ),
        Entry(
            menuTitle: "Timeline", label: "Timeline", key: "4",
            command: .timeline, group: .around, surface: .timeline
        ),
        Entry(
            menuTitle: "Apps", label: "Apps", key: "5",
            command: .apps, group: .around, surface: .apps, separatorBefore: true
        ),
        Entry(
            menuTitle: "Projects", label: "Projects", key: "6",
            command: .projects, group: .around, surface: .projects
        ),
        Entry(
            menuTitle: "Collections", label: "Collections", key: "7",
            command: .collections, group: .around, surface: .collections
        ),
        Entry(
            menuTitle: "Memories", label: "Memories", key: "8",
            command: .memories, group: .around, surface: .memories, separatorBefore: true
        ),
        Entry(
            menuTitle: "Story", label: "Story", key: "9",
            command: .story, group: .around, surface: .story
        ),
        // No shortcut: the digits run out at nine, and Canvas is a place you go to look
        // around rather than one you flick to. In the menu, absent from the table.
        Entry(
            menuTitle: "Canvas", label: "Canvas", key: "", modifiers: [],
            command: .canvas, surface: .canvas
        ),
        Entry(
            menuTitle: "Ambient Mode", label: "Ambient Mode", key: "a",
            modifiers: [.shift, .command], command: .ambient, group: .window,
            separatorBefore: true
        ),
        Entry(
            menuTitle: "Screensaver", label: "Screensaver", key: "s",
            modifiers: [.shift, .command], command: .screensaver, group: .window
        ),
        // A note on the stretch in progress, from wherever you are. The same panel the menu
        // bar opens, and the reason it has a key of its own: the moment worth writing down
        // is the one you are in, and reaching for the mouse is how it gets lost.
        Entry(
            menuTitle: "Note on This Session…", label: "Note on this session", key: "n",
            modifiers: [.shift, .command], command: .note, group: .window,
            separatorBefore: true
        ),
    ]

    /// Bound somewhere other than the View menu — by another menu macOS expects to own, or
    /// by a view. Listed so Settings can show them and the audit can check them.
    static let elsewhere: [Entry] = [
        Entry(label: "Find", key: "f", group: .around),
        Entry(label: "Back", key: "[", group: .around, boundInView: "RootView.swift"),
        Entry(label: "Settings", key: ",", group: .window, boundInView: "RootView.swift"),
        Entry(label: "Close", key: "w", group: .window),
        Entry(label: "Zoom in", key: "+", group: .canvas, boundInView: "CanvasView.swift"),
        Entry(label: "Zoom out", key: "-", group: .canvas, boundInView: "CanvasView.swift"),
        Entry(
            label: "Fit to the window", key: "0", group: .canvas, boundInView: "CanvasView.swift"
        ),
        // The three every keyboard surface answers. Bound by the palette's own key handling
        // and by `onExitCommand` rather than by a `keyboardShortcut`, so the audit is told
        // not to go looking for them.
        Entry(label: "Move through results", key: "↑ ↓", modifiers: [], group: .anywhere),
        Entry(label: "Open what is focused", key: "↩", modifiers: [], group: .anywhere),
        Entry(label: "Close what is open", key: "esc", modifiers: [], group: .anywhere),
    ]

    /// The keys that open and close ambient mode, written the way a Mac writes them.
    ///
    /// Read from the catalogue rather than typed out, because ambient mode's own exit hint
    /// says them: an ambient screen left open on another display cannot take the keyboard,
    /// so the hint promises this instead of Escape — and a hint that names a key nothing
    /// binds is the failure `tools/shortcut-audit.mjs` exists to prevent.
    static var ambientKeys: String {
        (menu.first { $0.command == .ambient }?.display ?? []).joined()
    }

    /// What a sidebar row should show on its trailing edge, or nothing when the surface has
    /// no key. Canvas is the one that has none — the digits run out at nine.
    static func keys(for surface: Navigation.Surface) -> [String]? {
        guard let entry = menu.first(where: { $0.surface == surface }), !entry.key.isEmpty else {
            return nil
        }
        return entry.display
    }

    /// Everything Settings shows, gathered under its headings in the order they are declared.
    static var settingsGroups: [(Group, [Entry])] {
        let all = menu + elsewhere
        return Group.allCases.compactMap { group in
            let rows = all.filter { $0.group == group }
            return rows.isEmpty ? nil : (group, rows)
        }
    }
}
