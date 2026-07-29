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
/// A window that can take the keyboard.
///
/// `NSWindow` refuses to become key when it is borderless, and a borderless window is what a
/// screensaver has to be. Without this the overlay came up, said "Press Esc to exit" across
/// the bottom, and then ignored Esc — every keystroke went to whatever was behind it.
///
/// **Except when it must not take it.** Ambient mode left open on a second screen is the one
/// case where taking the keyboard is exactly wrong: every keystroke would land in a window
/// showing a clock instead of in whatever you are writing. So the answer is a stored property
/// rather than `true`, and a pinned ambient window says no — which also means Escape does not
/// reach it, and the ✕ and ⇧⌘A are the ways out. Both keep working, because a click on a
/// non-key window is still delivered to it.
final class ScreensaverWindow: NSWindow {
    var takesKeyboard = true
    override var canBecomeKey: Bool { takesKeyboard }
    override var canBecomeMain: Bool { takesKeyboard }
}

/// The one symbol this library exposes.
///
/// Everything else stays internal: `main.swift` names `AppDelegate` and nothing besides, so
/// the split that bought previews cost six `public` keywords rather than a sweep through
/// 18,000 lines — this class, its `init`, and the four delegate methods a public type has to
/// expose to satisfy `NSApplicationDelegate`. Keep it that way: if a second symbol ever needs
/// exporting, the thing to move is the code that wanted it, not the boundary.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() { super.init() }

    private let model = AppModel()
    private lazy var history = HistoryModel(model: model)
    private let preferences = Preferences()
    private lazy var settings = SettingsModel(
        model: model, history: history, preferences: preferences
    )
    private lazy var export = ExportModel(model: model)
    private lazy var search = SearchModel(model: model, preferences: preferences)
    private lazy var memories = MemoriesModel(model: model)
    private lazy var collections = CollectionsModel(model: model)
    private lazy var week = WeekModel(model: model)
    private lazy var apps = AppsModel(model: model)
    private lazy var appHistory = AppHistoryModel(model: model)
    private lazy var projects = ProjectsModel(model: model, preferences: preferences)
    private lazy var story = StoryModel(model: model, preferences: preferences)
    private lazy var relationships = RelationshipsModel(model: model)
    private lazy var museum = MuseumModel(model: model, projects: projects)
    private lazy var canvas = CanvasModel(model: model, projects: projects, story: story)
    private lazy var contextual = ContextualMemoryModel(model: model, projects: projects, preferences: preferences)
    private lazy var palette = CommandPaletteModel(model: model, apps: apps, projects: projects)
    private lazy var timelineLayers = TimelineLayersModel(model: model)
    private lazy var notifications = NotificationsModel(model: model, preferences: preferences)
    private let navigation = Navigation()
    private var statusItem: NSStatusItem?
    private var menuBarPopover: NSPopover?
    /// Off unless somebody turned it on; see `UpdateModel`.
    private lazy var updates = UpdateModel(preferences: preferences)
    /// Off unless somebody chose a folder and a schedule; see `AutoBackupModel`.
    private lazy var backups = AutoBackupModel(model: model, preferences: preferences)
    /// Off unless somebody chose a folder and a schedule; see `ReportScheduleModel`.
    private lazy var reports = ReportScheduleModel(model: model, preferences: preferences)
    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    private var screensaverWindow: NSWindow?
    /// Ambient mode's own window. Separate from the screensaver's rather than a mode flag on
    /// one: the two are opened for opposite reasons — one while you are here, one once you
    /// have gone — and nothing good comes of being able to be in both at once.
    private var ambientWindow: NSWindow?
    private var idleWatch: Timer?
    private var backupWatch: Timer?
    private var resumeWatch: Timer?
    private var whatsNewWindow: NSWindow?
    /// The quick-note panel, while it is up.
    private var noteWindow: NSWindow?
    /// Which Settings pane to show when it next opens.
    private var settingsPane: SettingsView.Pane?
    /// Kept so its title can say what it will do rather than what it is.
    private var sidebarMenuItem: NSMenuItem?
    private var menuRefresh: Timer?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // One Replay at a time, and this is about the record rather than about tidiness.
        //
        // `ActivityStore.open()` closes any session left with no end — which is right after a
        // crash, and destructive while another copy is *running*: it sets `ended_at =
        // started_at, duration = 0` on the first instance's live session, so the stretch you
        // are in the middle of is zeroed by a second launch. Both copies then write to one
        // SQLite file with no busy timeout between them.
        //
        // So a second copy hands the first one the front and leaves, which is what a Mac app
        // does anyway. Found because somebody asked whether running two versions at once
        // could be the cause of a crash — it was not, but this was underneath the question.
        if let identifier = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication
                .runningApplications(withBundleIdentifier: identifier)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if let existing = others.first {
                existing.activate(options: [.activateAllWindows])
                NSApp.terminate(nil)
                return
            }
        } else {
            // No bundle identifier means no bundle: this is the bare executable, which is
            // what Product ▸ Run gives you in Xcode. Worth one line, because two things are
            // quietly different and both have cost an afternoon before.
            //
            // The guard above cannot run, so this copy and an installed Replay will both
            // record, into one SQLite file with no busy timeout between them. And there is
            // no Info.plist, so the version reads as `Replay.version` and the icon is
            // missing — neither is a bug to chase.
            let note = """
                Replay: running without a bundle — Info.plist, icon and version are absent, \
                and the one-copy-at-a-time guard is off. Quit any installed Replay first.
                  record: \(defaultDatabaseURL().path)
                Use ./scripts/make-app.sh for the real bundle, or set REPLAY_DB for a \
                scratch record.
                """
            FileHandle.standardError.write(Data((note + "\n").utf8))
        }

        model.start()
        // The tracker is told what to skip before the window appears, so an excluded app is
        // never recorded in the gap between launching and looking.
        model.applyExclusions(preferences.excludedBundleIDs)
        // A timed pause outlives the process it was set in — otherwise "until tomorrow" would
        // mean "until the next time Replay is opened", which is not what anybody agreed to.
        // A deadline that passed while the app was closed is simply over, and this is where
        // that is noticed.
        if Pause.stillPaused(until: preferences.pausedUntil, now: Date()) {
            model.setTracking(false)
        } else {
            preferences.pausedUntil = nil
        }
        // The daily update check, if it was ever turned on. Detached and unawaited: a
        // launch must not wait on a network, and a failed check is a non-event that will be
        // tried again tomorrow.
        Task { await updates.checkIfDue() }
        // And whether this launch is a version that has just arrived. Read before anything
        // is shown and written back immediately, so a crash between the two costs a note
        // rather than repeating one every launch forever.
        let launchNote = Updates.launchNote(
            previous: preferences.lastRunVersion,
            current: Replay.version,
            selfUpdated: preferences.selfUpdated
        )
        preferences.lastRunVersion = Replay.version
        preferences.selfUpdated = false
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

        // What the new version has to say for itself, if it is new.
        //
        // A window only for the update somebody asked for: they pressed a button, the app
        // vanished and came back, and "what did I just get" is the question they are holding.
        // An update that arrived by `brew upgrade` gets the banner instead — the same
        // information, in the place the offer would have been, waiting to be read rather than
        // asking to be. After `showWindow`, so the window it sits over already exists.
        switch launchNote {
        case .whatsNew: openWhatsNew()
        case .quietly: updates.noteInstalled(Replay.version)
        case .nothing: break
        }

        // The menu is rebuilt when it opens, but the *title* has to keep up on its own.
        // The Dock badge rides the same tick: it changes once an hour at most, so it does
        // not need one of its own.
        menuRefresh = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshStatusTitle()
                DockBadge.update(self.model, enabled: self.preferences.dockBadge)
            }
        }

        // Recaps are rewritten from the current settings on every launch, so a repeating
        // one carries figures that are a day old at most rather than however old the app
        // was when it was first switched on.
        Task {
            await notifications.refreshPermission()
            await notifications.reschedule()
        }

        // And the idle watch for whichever display it has been pointed at, if either.
        idleWatch = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIdleDisplay() }
        }

        // A pause that has run out, put back — at launch and every half minute after.
        resumeIfPauseIsOver()
        resumeWatch = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.resumeIfPauseIsOver() }
        }

        // A backup if one is owed, and then an hourly look.
        //
        // An hour rather than a day: this is not a daemon, and a Mac that was asleep at
        // whatever moment "daily" would have meant should still get its copy when it wakes.
        // `isDue` compares calendar days, so an hourly tick writes one file a day, not
        // twenty-four.
        backups.runIfDue()
        reports.runIfDue()
        backupWatch = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.backups.runIfDue()
                self?.reports.runIfDue()
            }
        }
    }

    /// Drift a display in after a spell of quiet — whichever one the settings name.
    ///
    /// Only while Replay's own window is in front, which is the whole reason this is
    /// tolerable: a thing that takes over the screen while you are working in something else
    /// is a fright, and one that appears over the app you were already looking at is a
    /// screensaver. Off by default either way.
    ///
    /// **And never over a display that is already up.** That was already true for ambient
    /// mode before the check below was added, but only by accident: ambient mode's window is
    /// key while it is up, so `window?.isKeyWindow` was false and the guard fell through for
    /// a reason that had nothing to do with ambient mode. Correct behaviour resting on an
    /// unrelated condition is a bug that has not happened yet — relax that line for any
    /// reason and this starts drifting in over a screen somebody is deliberately reading.
    /// Ambient mode is *specifically* the surface you look at without touching the keyboard,
    /// so the idle threshold trips while you sit there. Said explicitly now — and it matters
    /// twice over now that ambient mode can be what the timer raises, since an ambient screen
    /// left up by hand would otherwise be replaced by an identical one that dismisses itself.
    private func checkIdleDisplay() {
        let minutes = preferences.screensaverIdleMinutes
        // Never over a display that is already up **on the screen this one would take** — and
        // that qualifier is the fix. The guard used to be "no display is open anywhere", which
        // meant an ambient screen left running on a second monitor silently switched
        // auto-start off altogether: the thing you pinned somewhere else stopped the
        // screensaver ever arriving where you actually work. Two displays on one screen is
        // the thing worth preventing; two displays on two screens is the setup this app has.
        let target = displayScreen()
        let taken = [screensaverWindow, ambientWindow]
            .compactMap { $0?.screen }
            .contains { sameScreen($0, target) }
        guard minutes > 0, !taken, screensaverWindow == nil, NSApp.isActive,
              window?.isKeyWindow == true else { return }
        // The hours somebody confined it to, if they confined it to any. Read from the
        // calendar rather than from the timestamp so a span means what a person means by it
        // through a change of daylight saving, when the same hour can happen twice.
        if preferences.idleHoursLimited {
            let hour = Calendar.current.component(.hour, from: Date())
            guard IdleWindow.allows(
                hour: hour, from: preferences.idleFromHour, until: preferences.idleUntilHour
            ) else { return }
        }
        let idle = CGEventSource.secondsSinceLastEventType(
            .hidSystemState, eventType: .init(rawValue: ~0)!
        )
        guard idle >= Double(minutes) * 60 else { return }
        switch preferences.idleDisplay {
        case .screensaver: openScreensaver()
        case .ambient: showAmbient(auto: true)
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // Flush the open session so its duration is recorded rather than lost.
        preferences.lastSurface = navigation.surface.rawValue
        model.shutdown()
    }

    /// The Dock menu: what you would want without bringing the window forward first.
    ///
    /// Built fresh each time it opens, like the menu bar's, so it states the truth rather
    /// than a cached one.
    public func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
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
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

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
        // Where every Mac app puts it, which is the whole argument for putting it here: it
        // is the second thing under the app's own name, and people look for it there before
        // they look in Settings. Unlike the daily check this runs whether or not the switch
        // in Settings ▸ About is on — choosing it from a menu *is* the consent, and the
        // switch governs only whether Replay asks on its own.
        appMenu.addItem(
            withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: ""
        ).target = self
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

        // Built from `Shortcuts.menu` rather than written out here, so this menu and the
        // table in Settings cannot say different things about the same key. The wording, the
        // order and the separators are all decisions and all live in that one file.
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        for entry in Shortcuts.menu {
            if entry.separatorBefore { viewMenu.addItem(.separator()) }
            let item = viewMenu.addItem(
                withTitle: entry.menuTitle ?? entry.label,
                action: selector(for: entry.command),
                keyEquivalent: entry.key
            )
            item.keyEquivalentModifierMask = entry.flags
            item.target = self
            // Held because its title flips to "Show Sidebar" when the sidebar is hidden.
            if entry.command == .sidebar { self.sidebarMenuItem = item }
        }
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

        // macOS adds its own search field to any menu named "Help", and expects one to
        // exist. This app had none at all, so there was nowhere to reach the welcome, the
        // guide or the release notes from the menu bar.
        let helpItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(
            withTitle: "Welcome to Replay", action: #selector(showWelcome), keyEquivalent: ""
        ).target = self
        helpMenu.addItem(
            withTitle: "Replay Guide", action: #selector(openGuide), keyEquivalent: "?"
        ).target = self
        helpMenu.addItem(.separator())
        helpMenu.addItem(
            withTitle: "What's New", action: #selector(openWhatsNew), keyEquivalent: ""
        ).target = self
        helpItem.submenu = helpMenu
        main.addItem(helpItem)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    @objc private func openAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// A check somebody asked for, which is a different thing from the daily one.
    ///
    /// It has to answer either way. The banner is enough when there *is* a new version —
    /// it is right there in the window, so this brings the window forward and stops. When
    /// there is not, or the network is down, silence would read as a broken menu item, so
    /// this says so in a sheet and lets the user dismiss it. No sheet on success is
    /// deliberate: the answer is already on screen, and a dialog to say "look behind me"
    /// is a click that buys nothing.
    @objc private func checkForUpdates() {
        Task { @MainActor in
            await updates.checkNow()
            if updates.shouldOffer {
                showWindow()
                return
            }
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Replay \(Replay.version)"
            alert.informativeText = updates.failure ?? "This is the latest version."
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // ── menu bar ──────────────────────────────────────────────────────────────

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // `MenuBar.symbol`, and it matters: in the menu bar `clock.arrow.circlepath` is
        // Time Machine's glyph, so a status item wearing it reads as a system backup
        // service. The reference says so in a comment and this port used it anyway.
        item.button?.image = NSImage(
            systemSymbolName: MenuBar.symbol,
            accessibilityDescription: "Replay"
        )
        item.button?.imagePosition = .imageLeading
        // A popover rather than `item.menu`, and the two cannot coexist: setting `menu` makes
        // AppKit open it on mouse-down and the button's own action never fires. The menu's
        // contents did not survive as a right-click fallback for the same reason — everything
        // it held is a control in the popover now.
        item.button?.target = self
        item.button?.action = #selector(toggleMenuBarPopover)
        statusItem = item
        refreshStatusTitle()
    }

    /// Open the popover, or close it if it is already up.
    ///
    /// `.transient` so it closes when you click away, which is what a menu bar surface has to
    /// do — it is opened *during* something else, and dismissing it should not be a decision.
    @objc private func toggleMenuBarPopover() {
        guard let button = statusItem?.button else { return }
        if let popover = menuBarPopover, popover.isShown {
            popover.performClose(nil)
            return
        }
        // Read fresh. The popover is opened seconds after something changed as often as not,
        // and a stale figure in a surface this small is the whole content being wrong.
        model.reload()
        refreshStatusTitle()

        let popover = menuBarPopover ?? {
            let new = NSPopover()
            new.behavior = .transient
            new.animates = true
            menuBarPopover = new
            return new
        }()
        let hosting = NSHostingController(
            rootView: MenuBarPopoverView(
                model: model,
                preferences: preferences,
                onOpenToday: { [weak self] in self?.fromPopover { $0.openToday() } },
                onOpenTimeline: { [weak self] in self?.fromPopover { $0.openTimeline() } },
                onToggleTracking: { [weak self] in
                    // Deliberately does *not* close: pausing and watching the line change to
                    // "Tracking paused" is the confirmation, and a panel that vanishes leaves
                    // you wondering whether the click landed.
                    self?.toggleTracking()
                    self?.refreshStatusTitle()
                },
                onOpenSettings: { [weak self] in self?.fromPopover { $0.openSettings() } },
                onAddNote: { [weak self] in self?.fromPopover { $0.openNotePanel() } },
                onPause: { [weak self] span in
                    self?.pause(for: span)
                    self?.refreshStatusTitle()
                },
                onExcludeCurrent: { [weak self] in self?.fromPopover { $0.confirmExcludeCurrent() } },
                onQuit: { [weak self] in self?.fromPopover { $0.quit() } }
            )
            .environment(\.themeTint, preferences.themeColour.resolved)
            .tint(preferences.themeColour.colour)
            .preferredColorScheme(preferences.appearance.colorScheme)
        )
        // Size the panel to what is actually in it, every time it opens.
        //
        // The `NSPopover` is reused so the button can toggle it, and it remembers the content
        // size it was last given. The content does not stay one size: three recent sessions
        // is taller than none, a focus goal adds a bar, "Tracking paused" removes a row. So a
        // panel opened once while short stayed short, and taller content was clipped — off
        // the *top*, which took the header and the day's total with it and left the panel
        // opening mid-sentence.
        //
        // `.preferredContentSize` alone was not enough, because the size is asked for before
        // SwiftUI has laid the content out. Measuring the fitting size and setting it
        // explicitly is what makes it right on the first open as well as the fifth.
        hosting.sizingOptions = [.preferredContentSize]
        hosting.view.layoutSubtreeIfNeeded()
        popover.contentViewController = hosting
        popover.contentSize = hosting.view.fittingSize

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Without this the popover opens behind whatever you were in, because a status item
        // click does not activate the app.
        NSApp.activate(ignoringOtherApps: true)
        // Nothing in here takes the keyboard, and that is a property rather than an
        // oversight: a popover's window does not become key, so a text field placed in one
        // eats its first character and then dismisses the whole panel. The note is written
        // in a panel of its own for exactly that reason — see `openNotePanel`.
    }

    /// Stop recording the application in front, and erase what it already recorded.
    ///
    /// An alert rather than a row that simply does it. Every other control in the menu bar
    /// panel is reversible — pause, bookmark, a note — and this one is not: excluding an
    /// application also erases its history, which is what makes it a privacy action rather
    /// than a filter. So it names the application, says what it will remove, and the
    /// destructive button is the one that has to be chosen.
    @objc private func confirmExcludeCurrent() {
        guard let app = model.currentApp else { return }
        let alert = NSAlert()
        alert.messageText = String(format: Loc.t("Never record %@?"), app.name)
        alert.informativeText = Loc.t(
            "Replay will stop recording it, and will erase everything it has already recorded "
                + "for it. That cannot be undone — un-excluding later resumes recording but "
                + "does not bring the history back."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: Loc.t("Exclude and Erase"))
        alert.addButton(withTitle: Loc.t("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let bundleID = app.bundleID else { return }
        settings.setExcluded(
            KnownApp(
                applicationName: app.name, bundleIdentifier: bundleID, appPath: app.appPath
            ),
            true
        )
        model.reload()
        refreshStatusTitle()
    }

    /// The quick-note panel, on the stretch being lived in.
    ///
    /// Its own small window rather than a field in the menu bar panel, because a popover
    /// never becomes key and therefore cannot be typed in — see ``NoteView``. Floating, so it
    /// stays over whatever you were working in, which is the point of writing a note about
    /// the thing you are doing while you are still doing it.
    @objc func openNotePanel() {
        model.reload()
        guard let session = model.sessions.max(by: { $0.startedAt < $1.startedAt }) else { return }
        if let noteWindow {
            noteWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(
            rootView: Themed(preferences: preferences) {
                NoteView(
                    sessionTitle: session.title,
                    sessionStart: session.startedAt,
                    annotations: model.annotations,
                    onClose: { [weak self] in self?.closeNotePanel() }
                )
            }
        )
        let panel = NSPanel(contentViewController: hosting)
        panel.title = Loc.t("Note")
        panel.styleMask = [.titled, .closable, .utilityWindow]
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        noteWindow = panel
    }

    private func closeNotePanel() {
        noteWindow?.orderOut(nil)
        noteWindow = nil
    }

    /// Anything that opens a window closes the popover first, so the window does not appear
    /// underneath it.
    private func fromPopover(_ action: (AppDelegate) -> Void) {
        menuBarPopover?.performClose(nil)
        action(self)
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
        button.toolTip = MenuBar.tooltip(
            isRecording: model.isRecording, current: model.current?.applicationName
        )
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
                projects: projects,
                story: story,
                relationships: relationships,
                museum: museum,
                canvas: canvas,
                contextual: contextual,
                palette: palette,
                timelineLayers: timelineLayers,
                notifications: notifications,
                onOpenSettings: { [weak self] in self?.openSettings() },
                onOpenScreensaver: { [weak self] in self?.openScreensaver() },
                onOpenAmbient: { [weak self] in self?.openAmbient() },
                onOpenWhatsNew: { [weak self] in self?.openWhatsNew() },
                updates: updates
            )
        )
        // The window's size is its own. Without this the SwiftUI content drives it, and a
        // tall overlay — the welcome screen — grew the saved frame to 980x5580, which then
        // came back on the next launch as a window mostly off the bottom of the screen.
        // Same failure the screensaver had; the same one line fixes it.
        hosting.sizingOptions = []
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

    /// The one place a catalogue entry becomes a method call.
    ///
    /// `Shortcuts` deliberately holds no selectors: it is read by Settings, which has no
    /// business knowing about the app delegate, and by an audit script, which cannot run
    /// Swift at all. So the mapping lives here, next to the methods it names, and the
    /// compiler checks it is exhaustive.
    private func selector(for command: Shortcuts.Command?) -> Selector? {
        switch command {
        case .today: #selector(openToday)
        case .palette: #selector(openPalette)
        case .apps: #selector(openApps)
        case .week: #selector(openWeek)
        case .timeline: #selector(openTimeline)
        case .search: #selector(openSearch)
        case .memories: #selector(openMemories)
        case .collections: #selector(openCollections)
        case .projects: #selector(openProjects)
        case .story: #selector(openStory)
        case .canvas: #selector(openCanvas)
        case .sidebar: #selector(toggleSidebar)
        case .screensaver: #selector(openScreensaver)
        case .ambient: #selector(openAmbient)
        case .note: #selector(openNotePanel)
        case nil: nil
        }
    }

    @objc private func openToday() {
        model.reload()
        navigation.show(.today)
        showWindow()
    }

    /// Which screen a full-screen display takes.
    ///
    /// `NSScreen.main` is the screen with keyboard focus, which is where the person is
    /// looking, and it is still the answer when nothing has been named. (`window?.screen` was
    /// tried first, long ago, and put the overlay on whichever display the main window's
    /// restored frame happened to sit on — the wrong one, silently.)
    ///
    /// A named screen is matched by `localizedName`, which is what the picker shows, and a
    /// name that matches nothing falls through to the keyboard's screen rather than to
    /// nothing at all. That is the unplugged case, and it has to be silent: a laptop that is
    /// closed and opened twice a day would otherwise be a settings error twice a day.
    private func displayScreen() -> NSScreen? {
        let name = preferences.displayScreenName
        if !name.isEmpty, let named = NSScreen.screens.first(where: { $0.localizedName == name }) {
            return named
        }
        return NSScreen.main ?? window?.screen ?? NSScreen.screens.first
    }

    /// Whether two screens are the same physical display.
    ///
    /// By display id rather than by `==`: `NSScreen` objects are recreated when the screen
    /// arrangement changes, so identity comparison answers "is this the same object" and the
    /// question here is "is this the same piece of glass".
    private func sameScreen(_ a: NSScreen?, _ b: NSScreen?) -> Bool {
        guard let a, let b else { return false }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (a.deviceDescription[key] as? NSNumber) == (b.deviceDescription[key] as? NSNumber)
    }

    /// Raise the screensaver over everything, on the screen the window is on.
    ///
    /// A borderless window at the screen-saver level rather than a sheet or a full-screen
    /// space: it should cover the menu bar and the Dock the way a real screensaver does, and
    /// it should not take the main window into a space you then have to come back out of.
    /// Deliberately *not* started on a timer — the reference offers that, but a thing that
    /// takes over the screen on its own is the sort of surprise this app should not spring.
    @objc private func openScreensaver() {
        if let screensaverWindow {
            screensaverWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // The two never overlap *on one screen*. Asking for the screensaver while ambient
        // mode was up used to stack one over the other at the same window level; closing it
        // unconditionally then meant a pinned ambient screen on another monitor was thrown
        // away by a screensaver that was never going to cover it.
        let screen = displayScreen()
        if sameScreen(ambientWindow?.screen, screen) { closeAmbient() }
        // Loaded before the view exists: the screensaver measures its own column to know
        // how far to drift, so everything it will show has to be in hand first.
        if !memories.loaded { memories.load() }
        let hosting = NSHostingController(
            rootView: Themed(preferences: preferences, forcing: .dark) {
                ScreensaverView(
                    model: model,
                    memories: memories,
                    preferences: preferences,
                    onExit: { [weak self] in self?.closeScreensaver() }
                )
                .preferredColorScheme(.dark)
            }
        )
        // Without this the SwiftUI content drives the window's size, and this content is a
        // deliberately very tall column — the first version produced a 1728x2888 window.
        hosting.sizingOptions = []
        let saver = ScreensaverWindow(contentViewController: hosting)
        saver.styleMask = [.borderless]
        saver.level = .screenSaver
        saver.isOpaque = true
        // Without this a window is never sent `.mouseMoved` at all, so the local monitor
        // watching for it never fires: "Exit on mouse movement" had nothing to hear.
        saver.acceptsMouseMovedEvents = true
        saver.backgroundColor = .black
        saver.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        saver.isReleasedWhenClosed = false
        if let frame = screen?.frame { saver.setFrame(frame, display: true) }
        saver.makeKeyAndOrderFront(nil)
        // Again after ordering front: a borderless window can be nudged as it is shown.
        if let frame = screen?.frame { saver.setFrame(frame, display: true) }
        NSApp.activate(ignoringOtherApps: true)
        screensaverWindow = saver
    }

    /// Ambient mode, over everything, on the screen you are looking at.
    ///
    /// The same window recipe as the screensaver — borderless, screen-saver level, joins all
    /// spaces — because the requirement is the same: cover the menu bar and the Dock without
    /// dragging the main window into a full-screen space you then have to come back out of.
    /// The menu, the palette and the sidebar all ask for it by hand; only the idle watch
    /// asks for it any other way, and what it gets back has to behave differently.
    ///
    /// **Asking for it again closes it**, rather than raising the one already up. A mode is
    /// something you are either in or not, so the command that enters it is the command that
    /// leaves it — and once ambient mode can be left open on another screen without the
    /// keyboard, ⇧⌘A is the only way out that does not involve aiming at a disc on a display
    /// you are not looking at.
    @objc private func openAmbient() {
        if ambientWindow != nil {
            closeAmbient()
        } else {
            showAmbient(auto: false)
        }
    }

    private func showAmbient(auto: Bool) {
        if let ambientWindow {
            ambientWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let screen = displayScreen()
        if sameScreen(screensaverWindow?.screen, screen) { closeScreensaver() }
        // Left up, or handed back the moment you touch anything?
        //
        // Only a screen that is *not* the one the window is on can be left up. Ambient mode
        // takes a whole display; honouring "leave it open" on the display you are working in
        // would cover the work with a clock and no keyboard to dismiss it — the setting asks
        // for a second screen, and this is where that is checked rather than assumed.
        let pinned = preferences.ambientStaysOpen
            && !sameScreen(screen, window?.screen ?? NSScreen.main)
        let hosting = NSHostingController(
            rootView: Themed(preferences: preferences, forcing: .dark) {
                AmbientView(
                    model: model, preferences: preferences,
                    // Only a screen that arrived on its own leaves on its own — and only if
                    // it is in the way. A pinned one is somewhere else by definition.
                    dismissOnActivity: auto && !pinned,
                    takesKeyboard: !pinned,
                    onExit: { [weak self] in self?.closeAmbient() }
                )
                    .preferredColorScheme(.dark)
            }
        )
        hosting.sizingOptions = []
        let ambient = ScreensaverWindow(contentViewController: hosting)
        ambient.styleMask = [.borderless]
        ambient.level = .screenSaver
        ambient.isOpaque = true
        // Same as the screensaver's: an auto-started ambient screen leaves on movement, and
        // movement is not delivered to a window that has not said it wants it.
        ambient.acceptsMouseMovedEvents = true
        ambient.backgroundColor = .black
        ambient.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ambient.isReleasedWhenClosed = false
        ambient.takesKeyboard = !pinned
        if let frame = screen?.frame { ambient.setFrame(frame, display: true) }
        if pinned {
            // `orderFrontRegardless` rather than `makeKeyAndOrderFront`, and no `activate`:
            // a display you leave running must not pull the application forward, or opening
            // it would take you out of whatever you were typing in — which is the one thing
            // this whole setting exists to prevent.
            ambient.orderFrontRegardless()
        } else {
            ambient.makeKeyAndOrderFront(nil)
        }
        // Again after ordering front: a borderless window can be nudged as it is shown.
        if let frame = screen?.frame { ambient.setFrame(frame, display: true) }
        if !pinned { NSApp.activate(ignoringOtherApps: true) }
        ambientWindow = ambient
    }

    /// Take it down, and give the keyboard back only if it had it.
    ///
    /// A pinned ambient screen never took focus, so pulling the main window forward on the
    /// way out would move somebody out of the application they were working in — the same
    /// interruption in reverse.
    private func closeAmbient() {
        let hadKeyboard = (ambientWindow as? ScreensaverWindow)?.takesKeyboard ?? true
        ambientWindow?.orderOut(nil)
        ambientWindow = nil
        if hadKeyboard { window?.makeKeyAndOrderFront(nil) }
    }

    private func closeScreensaver() {
        screensaverWindow?.orderOut(nil)
        screensaverWindow = nil
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openCanvas() {
        canvas.load()
        navigation.show(.canvas)
        showWindow()
    }

    @objc private func openStory() {
        story.load()
        navigation.show(.story)
        showWindow()
    }

    @objc private func openProjects() {
        projects.load()
        navigation.show(.projects)
        showWindow()
    }

    /// Put the welcome back. The window comes forward with it, since it replaces what is in
    /// there rather than opening beside it.
    @objc private func showWelcome() {
        preferences.seenWelcome = false
        showWindow()
    }

    /// Settings, on the pane that answers questions.
    @objc private func openGuide() {
        // Set before opening, since the window is built from it. Cleared afterwards so the
        // next plain ⌘, opens on General as it should.
        settingsPane = .guide
        closeSettings()
        openSettings()
        settingsPane = nil
    }

    private func closeSettings() {
        settingsWindow?.close()
        settingsWindow = nil
    }

    /// Not private: Settings ▸ About offers the same thing, and the window is raised by the
    /// delegate because it is a window rather than a sheet.
    @objc func openWhatsNew() {
        if let whatsNewWindow {
            whatsNewWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(
            rootView: Themed(preferences: preferences) {
                WhatsNewView(onClose: { [weak self] in self?.closeWhatsNew() })
            }
        )
        // Its size is its own, as everywhere else here — twice bitten.
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = "What's New"
        window.setContentSize(
            NSSize(width: Design.Layout.whatsNewWidth, height: Design.Layout.whatsNewHeight)
        )
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        whatsNewWindow = window
    }

    private func closeWhatsNew() {
        whatsNewWindow?.orderOut(nil)
        whatsNewWindow = nil
    }

    @objc private func openPalette() {
        showWindow()
        palette.open = true
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
            rootView: Themed(preferences: preferences) {
                SettingsView(
                    model: model, settings: settings, export: export,
                    preferences: preferences, contextual: contextual,
                    notifications: notifications, updates: updates, backups: backups,
                    reports: reports,
                    initialPane: settingsPane ?? .general
                )
                // Same reason as the main window's: a language is chosen *in* this window,
                // so this is the one that has to answer in the new one immediately.
                .id(preferences.languageCode)
            }
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
        // Resuming by hand clears any deadline: the pause is over because somebody said so,
        // and a stale "resumes at 3pm" hanging off a recording app would be a lie in the one
        // place this feature exists to keep honest.
        setTracking(!model.isRecording, until: nil)
    }

    /// Pause or resume, and say when it ends.
    ///
    /// One door for both, because the deadline and the tracker have to move together — a
    /// paused tracker with no stored end is an indefinite pause, and a stored end with a
    /// running tracker is a countdown to nothing.
    private func setTracking(_ recording: Bool, until: Date?) {
        preferences.pausedUntil = recording ? nil : until
        model.setTracking(recording)
        refreshStatusTitle()
    }

    /// Pause for a span, and let it end itself.
    private func pause(for span: Pause.Span) {
        setTracking(false, until: Pause.ends(span, from: Date()))
    }

    /// Put recording back when a timed pause has run out.
    ///
    /// Polled rather than scheduled at the exact moment, because the exact moment is the one
    /// a sleeping Mac misses: a timer set for 3pm on a laptop that is shut at 2pm fires late
    /// or not at all, while a comparison against the clock is right the first time it runs
    /// after waking. Thirty seconds is well inside the resolution anything here is read at.
    private func resumeIfPauseIsOver() {
        guard let until = preferences.pausedUntil else { return }
        guard Pause.isOver(until: until, now: Date()) else { return }
        setTracking(true, until: nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
