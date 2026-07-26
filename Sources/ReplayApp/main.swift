import AppKit
import ReplayCore
import SwiftUI

/// Replay, natively.
///
/// A menu bar item is the app's real home — it records all day whether or not a window is
/// open — with Today in a window when you want to look. Built as an AppKit delegate rather
/// than a SwiftUI `App` so the status item, the window, and the tracker's lifetime are all
/// explicit; a menu-bar app whose window can be closed and reopened is fiddly to express in
/// the SwiftUI lifecycle and trivial here.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private lazy var history = HistoryModel(model: model)
    private let preferences = Preferences()
    private lazy var settings = SettingsModel(
        model: model, history: history, preferences: preferences
    )
    private lazy var export = ExportModel(model: model)
    private lazy var search = SearchModel(model: model)
    private lazy var memories = MemoriesModel(model: model)
    private lazy var collections = CollectionsModel(model: model)
    private lazy var week = WeekModel(model: model)
    private lazy var apps = AppsModel(model: model)
    private lazy var appHistory = AppHistoryModel(model: model)
    private let navigation = Navigation()
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    /// Kept so its title can say what it will do rather than what it is.
    private var sidebarMenuItem: NSMenuItem?
    private var menuRefresh: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        // The tracker is told what to skip before the window appears, so an excluded app is
        // never recorded in the gap between launching and looking.
        model.applyExclusions(preferences.excludedBundleIDs)
        // A pinned "open on" is an instruction and wins; otherwise come back to where the
        // window was left, which is what a Mac app does.
        if let pinned = Navigation.Surface(rawValue: preferences.launchSurface.label),
           preferences.launchSurface != .today {
            navigation.surface = pinned
        } else if let last = Navigation.Surface(rawValue: preferences.lastSurface) {
            navigation.surface = last
        }
        if preferences.menuBarOnly { NSApp.setActivationPolicy(.accessory) }
        installApplicationMenu()
        installStatusItem()
        showWindow()

        // The menu is rebuilt when it opens, but the *title* has to keep up on its own.
        menuRefresh = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatusTitle() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Flush the open session so its duration is recorded rather than lost.
        preferences.lastSurface = navigation.surface.rawValue
        model.shutdown()
    }

    /// The Dock menu: what you would want without bringing the window forward first.
    ///
    /// Built fresh each time it opens, like the menu bar's, so it states the truth rather
    /// than a cached one.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        model.reload()
        let menu = NSMenu()

        if let summary = model.summary, summary.switches > 0 {
            let today = NSMenuItem(
                title: "\(formatDurationShort(summary.activeSeconds)) active today",
                action: nil, keyEquivalent: ""
            )
            today.isEnabled = false
            menu.addItem(today)
            menu.addItem(.separator())
        }

        menu.addItem(withTitle: "Open Today", action: #selector(openToday), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Search…", action: #selector(findInReplay), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: model.isRecording ? "Pause Recording" : "Resume Recording",
            action: #selector(toggleTracking), keyEquivalent: ""
        ).target = self
        return menu
    }

    /// Closing the window must not quit: Replay keeps recording, and the menu bar is where
    /// it lives.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // ── the application menu ──────────────────────────────────────────────────

    /// The menu bar every Mac app has, which this one was missing.
    ///
    /// Built by hand because there is no nib: an app started from top-level code gets no
    /// main menu at all, and without one ⌘, ⌘W and ⌘Q do nothing, the window cannot be
    /// closed from the keyboard, and — the part that actually bites — **⌘C and ⌘V do not
    /// work in a note or a tag field**, because those are menu-driven on macOS rather than
    /// built into the text system.
    private func installApplicationMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Replay", action: #selector(openAbout), keyEquivalent: "")
            .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Hide Replay",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = appMenu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Replay", action: #selector(quit), keyEquivalent: "q")
            .target = self
        appItem.submenu = appMenu
        main.addItem(appItem)

        // Edit exists for the text fields rather than for its own sake — a note field with
        // no Paste is broken in a way users notice immediately.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"
        )
        editMenu.addItem(.separator())
        // Find lives in Edit, where every Mac app puts it, and goes to the search field
        // rather than to a surface — ⌘F means "let me type a query", not "show me search".
        editMenu.addItem(withTitle: "Find…", action: #selector(findInReplay), keyEquivalent: "f")
            .target = self
        editItem.submenu = editMenu
        main.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let sidebarItem = viewMenu.addItem(
            withTitle: "Hide Sidebar", action: #selector(toggleSidebar), keyEquivalent: "s"
        )
        sidebarItem.keyEquivalentModifierMask = [.command, .control]
        sidebarItem.target = self
        self.sidebarMenuItem = sidebarItem
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Today", action: #selector(openToday), keyEquivalent: "1")
            .target = self
        viewMenu.addItem(withTitle: "Apps", action: #selector(openApps), keyEquivalent: "2")
            .target = self
        viewMenu.addItem(withTitle: "This Week", action: #selector(openWeek), keyEquivalent: "3")
            .target = self
        viewMenu.addItem(withTitle: "Timeline", action: #selector(openTimeline), keyEquivalent: "4")
            .target = self
        // Numbered in sidebar order. Search is ⌘3 rather than ⌘F: ⌘F is Find, and
        // `.searchable` binds it to focus the field — a menu item that stole it switched
        // surfaces and then swallowed the keystrokes meant for the search box.
        viewMenu.addItem(withTitle: "Search", action: #selector(openSearch), keyEquivalent: "5")
            .target = self
        viewMenu.addItem(withTitle: "Memories", action: #selector(openMemories), keyEquivalent: "6")
            .target = self
        viewMenu.addItem(
            withTitle: "Collections", action: #selector(openCollections), keyEquivalent: "7"
        ).target = self
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"
        )
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    @objc private func openAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // ── menu bar ──────────────────────────────────────────────────────────────

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "clock.arrow.circlepath",
            accessibilityDescription: "Replay"
        )
        item.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        refreshStatusTitle()
    }

    /// Deliberately quiet: an icon, and a short label only while something is worth saying.
    private func refreshStatusTitle() {
        guard let button = statusItem?.button else { return }
        if !model.isRecording {
            button.title = " Paused"
        } else if let seconds = model.summary?.activeSeconds, seconds >= 60 {
            button.title = " \(formatDurationShort(seconds))"
        } else {
            button.title = ""
        }
        button.toolTip = model.statusLine
    }

    private func showWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(
            rootView: RootView(
                model: model, history: history, navigation: navigation,
                preferences: preferences, export: export, search: search, memories: memories,
                collections: collections,
                week: week,
                apps: apps,
                appHistory: appHistory,
                onOpenSettings: { [weak self] in self?.openSettings() }
            )
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Replay"
        window.setContentSize(
            NSSize(width: Design.Layout.windowWidth, height: Design.Layout.windowHeight)
        )
        window.contentMinSize = NSSize(
            width: Design.Layout.windowMinWidth, height: Design.Layout.windowMinHeight
        )
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        // The system restores the frame; `center()` is only the first-run fallback.
        window.center()
        window.setFrameAutosaveName("ReplayMainWindow")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    // ── menu actions ──────────────────────────────────────────────────────────

    @objc private func openToday() {
        model.reload()
        navigation.show(.today)
        showWindow()
    }

    @objc private func openApps() {
        apps.load()
        navigation.show(.apps)
        showWindow()
    }

    @objc private func openWeek() {
        week.load()
        navigation.show(.week)
        showWindow()
    }

    @objc private func openTimeline() {
        history.reload()
        navigation.show(.timeline)
        showWindow()
    }

    @objc private func toggleSidebar() {
        navigation.toggleSidebar()
        sidebarMenuItem?.title = navigation.sidebarCollapsed ? "Show Sidebar" : "Hide Sidebar"
        showWindow()
    }

    @objc private func findInReplay() {
        navigation.focusSearch()
        showWindow()
    }

    @objc private func openSearch() {
        search.load()
        navigation.show(.search)
        showWindow()
    }

    @objc private func openMemories() {
        memories.load()
        navigation.show(.memories)
        showWindow()
    }

    @objc private func openCollections() {
        collections.opened = nil
        collections.load()
        navigation.show(.collections)
        showWindow()
    }

    /// Settings in its own window, as a Mac app does — not a third tab in the main one.
    @objc private func openSettings() {
        settings.reload()
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(
            rootView: SettingsView(
                model: model, settings: settings, export: export, preferences: preferences
            )
        )
        // The window takes its size from the pane rather than the other way round, so
        // switching tabs resizes it the way System Settings does — and a short pane is a
        // short window instead of one with air at the bottom.
        // A split view fills what it is given rather than asking for a size, so the
        // window sets its own — and can be resized, which a two-column settings window
        // should be.
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = "Replay Settings"
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.setContentSize(
            NSSize(width: Design.Layout.settingsWidth, height: Design.Layout.settingsHeight)
        )
        window.contentMinSize = NSSize(
            width: Design.Layout.settingsSidebarWidth + Design.Layout.settingsDetailWidth,
            height: Design.Layout.settingsHeight
        )
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("ReplaySettingsWindow")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc private func toggleTracking() {
        model.setTracking(!model.isRecording)
        refreshStatusTitle()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

extension AppDelegate: NSMenuDelegate {
    /// Rebuilt each time it opens, so it always states the truth rather than a cached one.
    func menuNeedsUpdate(_ menu: NSMenu) {
        model.reload()
        refreshStatusTitle()
        menu.removeAllItems()

        let status = NSMenuItem(title: model.statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if let summary = model.summary, summary.switches > 0 {
            let detail = NSMenuItem(
                title: "\(formatDurationShort(summary.activeSeconds)) active · "
                    + "\(summary.sessionCount) \(summary.sessionCount == 1 ? "session" : "sessions")",
                action: nil,
                keyEquivalent: ""
            )
            detail.isEnabled = false
            menu.addItem(detail)

            if let top = summary.mostUsed {
                let topItem = NSMenuItem(
                    title: "Most used: \(top.applicationName) · \(formatDurationShort(top.seconds))",
                    action: nil,
                    keyEquivalent: ""
                )
                topItem.isEnabled = false
                menu.addItem(topItem)
            }
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Today", action: #selector(openToday), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Open Timeline", action: #selector(openTimeline), keyEquivalent: "")
            .target = self
        menu.addItem(
            withTitle: model.isRecording ? "Pause Recording" : "Resume Recording",
            action: #selector(toggleTracking),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Replay", action: #selector(quit), keyEquivalent: "q").target = self
    }
}

// A `@main` type cannot coexist with top-level code, so the app is started explicitly.
// `.regular` rather than `.accessory` for now: a Dock icon is convenient while the UI is
// being built, and menu-bar-only becomes a setting later, as it is in the Glaze app.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
