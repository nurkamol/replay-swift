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
        case collections, projects, story, canvas, sidebar, screensaver
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

    /// The View menu, in the order it is built. Separators are part of the order because the
    /// grouping is a decision — Today and the palette lead, the numbered surfaces follow.
    static let menu: [Entry] = [
        Entry(
            menuTitle: "Hide Sidebar", label: "Show or hide the sidebar", key: "s",
            modifiers: [.control, .command], command: .sidebar, group: .window
        ),
        Entry(
            menuTitle: "Today", label: "Today", key: "1",
            command: .today, group: .around, separatorBefore: true
        ),
        Entry(
            menuTitle: "Go to Anything…", label: "Go to anything", key: "k",
            command: .palette, group: .around
        ),
        Entry(
            menuTitle: "Apps", label: "Apps", key: "2",
            command: .apps, group: .around, separatorBefore: true
        ),
        Entry(menuTitle: "This Week", label: "This Week", key: "3", command: .week, group: .around),
        Entry(
            menuTitle: "Timeline", label: "Timeline", key: "4",
            command: .timeline, group: .around
        ),
        // Numbered in sidebar order. Search is ⌘5 rather than ⌘F: ⌘F is Find, and
        // `.searchable` binds it to focus the field — a menu item that stole it switched
        // surfaces and then swallowed the keystrokes meant for the search box.
        Entry(menuTitle: "Search", label: "Search", key: "5", command: .search, group: .around),
        Entry(
            menuTitle: "Memories", label: "Memories", key: "6",
            command: .memories, group: .around
        ),
        Entry(
            menuTitle: "Collections", label: "Collections", key: "7",
            command: .collections, group: .around
        ),
        Entry(
            menuTitle: "Projects", label: "Projects", key: "8",
            command: .projects, group: .around
        ),
        Entry(menuTitle: "Story", label: "Story", key: "9", command: .story, group: .around),
        // No shortcut: the digits run out at nine, and Canvas is a place you go to look
        // around rather than one you flick to. In the menu, absent from the table.
        Entry(menuTitle: "Canvas", label: "Canvas", key: "", modifiers: [], command: .canvas),
        Entry(
            menuTitle: "Screensaver", label: "Screensaver", key: "s",
            modifiers: [.shift, .command], command: .screensaver, group: .window,
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

    /// Everything Settings shows, gathered under its headings in the order they are declared.
    static var settingsGroups: [(Group, [Entry])] {
        let all = menu + elsewhere
        return Group.allCases.compactMap { group in
            let rows = all.filter { $0.group == group }
            return rows.isEmpty ? nil : (group, rows)
        }
    }
}
