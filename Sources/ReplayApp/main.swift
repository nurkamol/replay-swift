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
    private let navigation = Navigation()
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    private var menuRefresh: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        // The tracker is told what to skip before the window appears, so an excluded app is
        // never recorded in the gap between launching and looking.
        model.applyExclusions(preferences.excludedBundleIDs)
        navigation.surface = preferences.launchSurface == .timeline ? .timeline : .today
        if preferences.menuBarOnly { NSApp.setActivationPolicy(.accessory) }
        installStatusItem()
        showWindow()

        // The menu is rebuilt when it opens, but the *title* has to keep up on its own.
        menuRefresh = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatusTitle() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Flush the open session so its duration is recorded rather than lost.
        model.shutdown()
    }

    /// Closing the window must not quit: Replay keeps recording, and the menu bar is where
    /// it lives.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

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
                preferences: preferences, export: export
            )
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Replay"
        window.setContentSize(NSSize(width: 680, height: 760))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
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

    @objc private func openTimeline() {
        history.reload()
        navigation.show(.timeline)
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
        let window = NSWindow(contentViewController: hosting)
        window.title = "Replay Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
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
