import ReplayCore
import SwiftUI

/// Settings, built on `Form` rather than on hand-laid stacks.
///
/// The first version reimplemented what `.formStyle(.grouped)` already does — a label
/// column, a control column, secondary text under a row — and did it worse. The label column
/// was whatever space the controls left over, so descriptions wrapped into paragraphs; and
/// every pane scrolled, with its last section below the fold. A macOS settings pane does not
/// scroll for content that fits, and does not wrap its labels.
///
/// So this uses the platform's own container. `LabeledContent` puts the control where the
/// system puts it, `Section` draws the grouping and its footnote, and each pane sizes to its
/// own content.
///
/// Only what this port can honour: a control for a feature that is not built is a promise
/// the app breaks.
struct SettingsView: View {
    let model: AppModel
    let settings: SettingsModel
    let export: ExportModel
    @Bindable var preferences: Preferences
    let contextual: ContextualMemoryModel
    let notifications: NotificationsModel

    /// The panes, in the order they are worth reaching for.
    /// Not private: the Help menu opens Settings on a chosen pane.
    enum Pane: String, CaseIterable, Identifiable, Hashable {
        case general = "General", privacy = "Privacy", data = "Data"
        case shortcuts = "Shortcuts", guide = "Guide", about = "About"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .privacy: "hand.raised"
            case .data: "internaldrive"
            case .shortcuts: "keyboard"
            case .guide: "questionmark.circle"
            case .about: "info.circle"
            }
        }

        /// The tint behind each glyph, as System Settings does it. Colour here is
        /// wayfinding rather than decoration: it makes a pane recognisable at a glance
        /// before its name is read.
        var tint: Color {
            switch self {
            case .general: .gray
            case .privacy: .blue
            case .data: .indigo
            case .shortcuts: .purple
            case .guide: .teal
            case .about: .secondary
            }
        }
    }

    /// Which pane to show. Given by the caller so Help ▸ Replay Guide lands on the Guide
    /// rather than on General with the guide one click away.
    var initialPane: Pane = .general

    @State private var pane: Pane = .general

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { item in
                NavigationLink(value: item) {
                    Label {
                        Text(item.rawValue)
                    } icon: {
                        // A tinted rounded tile rather than a bare glyph — the shape
                        // System Settings uses, and the reason its list reads as a set of
                        // places rather than a list of words.
                        Image(systemName: item.symbol)
                            .font(Design.Text.detail)
                            .foregroundStyle(.white)
                            .frame(
                                width: Design.Icon.settingsTile,
                                height: Design.Icon.settingsTile
                            )
                            .background(
                                item.tint,
                                in: RoundedRectangle(cornerRadius: Design.Radius.small)
                            )
                    }
                }
            }
            .navigationSplitViewColumnWidth(Design.Layout.settingsSidebarWidth)
            .onAppear { pane = initialPane }
        } detail: {
            Group {
                switch pane {
                case .general: GeneralTab(model: model, preferences: preferences, contextual: contextual, notifications: notifications)
                case .privacy:
                    PrivacyTab(model: model, settings: settings, preferences: preferences)
                case .data: DataTab(settings: settings, export: export, preferences: preferences)
                case .shortcuts: ShortcutsTab()
                case .guide: GuideTab()
                case .about: AboutTab()
                }
            }
            .navigationTitle(pane.rawValue)
        }
        .onAppear { settings.reload() }
    }
}

// ── shared furniture ──────────────────────────────────────────────────────────

/// A settings pane: a grouped form at the standard width, sized to its own content.
///
/// The width is fixed because a settings window's is; the height is not, so a short pane is
/// a short window rather than a tall one with air at the bottom.
private struct PaneForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .frame(minWidth: Design.Layout.settingsDetailWidth)
    }
}

/// A section's footnote, aligned the way the system aligns them.
///
/// `Form` centres a footer by default in this configuration, which reads as a caption for
/// the window rather than a note about the section above it.
private struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            // Both are needed: the frame places a short line, `multilineTextAlignment`
            // places the wrapped ones, which a Form otherwise centres.
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What an action just did, in the place the system puts a footnote.
private struct StatusFooter: View {
    var settings: SettingsModel?
    var export: ExportModel?

    private var error: String? { settings?.errorMessage ?? export?.errorMessage }
    private var status: String? { settings?.status ?? export?.status }

    var body: some View {
        if let error {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(Design.Text.detail)
        } else if let status {
            Text(status)
                .foregroundStyle(.secondary)
                .font(Design.Text.detail)
        }
    }
}

// ── general ───────────────────────────────────────────────────────────────────

private struct GeneralTab: View {
    let model: AppModel
    @Bindable var preferences: Preferences
    /// Reloaded when a memory setting changes, so the card on Today reflects the choice
    /// immediately rather than at the next launch.
    let contextual: ContextualMemoryModel
    let notifications: NotificationsModel

    /// Asking is what prompts macOS. Switching one *off* never asks — a request should only
    /// ever follow from wanting the thing it is for.
    private func enableNotification(_ on: Bool) async {
        if on, notifications.permission != .granted {
            let granted = await notifications.request()
            if !granted {
                preferences.dailySummary = false
                preferences.weeklyRecap = false
                preferences.onThisDayNotice = false
            }
        }
        await notifications.reschedule()
    }

    /// "6:00 PM" — a plain hour, in the locale's own clock.
    private static func hourLabel(_ hour: Int) -> String {
        var parts = DateComponents()
        parts.hour = hour
        parts.minute = 0
        guard let date = Calendar.current.date(from: parts) else { return "\(hour):00" }
        return date.formatted(.dateTime.hour().minute())
    }

    /// Zero is how "no goal" is spelled in the picker; `nil` is how it is stored.
    private var goalSelection: Binding<Int> {
        Binding(
            get: { preferences.focusGoalMinutes ?? 0 },
            set: { preferences.focusGoalMinutes = $0 == 0 ? nil : $0 }
        )
    }

    /// Clamped on the way in, so a typed target cannot land outside the bounds the
    /// reference enforces — four minutes or forty hours is not a daily focus goal.
    private var customMinutes: Binding<Int> {
        Binding(
            get: { preferences.focusGoalMinutes ?? Goals.customDefaultMinutes },
            set: {
                preferences.focusGoalMinutes = min(
                    Goals.maxCustomMinutes, max(Goals.minCustomMinutes, $0)
                )
            }
        )
    }

    private var keepsGoal: Bool { preferences.focusGoalMinutes != nil }

    /// One colour, as a dot you can click.
    ///
    /// The chosen one is ringed rather than ticked: a checkmark drawn on a coloured disc is
    /// unreadable on the pale ones and invisible on yellow.
    private func swatch(_ choice: ThemeColour) -> some View {
        let chosen = preferences.themeColour == choice
        return Button {
            preferences.themeColour = choice
        } label: {
            Circle()
                .fill(choice.swatch)
                .frame(width: Design.Layout.swatch, height: Design.Layout.swatch)
                .overlay {
                    // Only "Match System" says what it is on its face; the rest are the
                    // colour and need no label.
                    if choice == .system {
                        Image(systemName: "desktopcomputer")
                            .font(Design.Text.pillGlyph)
                            .foregroundStyle(.white)
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(.primary, lineWidth: Design.Layout.swatchRing)
                        .padding(-Design.Layout.swatchRingGap)
                        .opacity(chosen ? 1 : 0)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(choice.label)
        .accessibilityLabel(choice.label)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }

    var body: some View {
        PaneForm {
            Section {
                Picker("Appearance", selection: $preferences.appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                .horizontalRadioGroupLayout()

                // Swatches rather than a list of colour names, because the choice is the
                // colour: reading "Pink" and picking it from a menu is a slower way to do
                // what looking at a row of dots does at a glance. "Match System" leads,
                // because following the accent already chosen in System Settings is the
                // right default and the row should say so.
                LabeledContent("Theme colour") {
                    HStack(spacing: Design.Space.snug) {
                        ForEach(ThemeColour.allCases) { choice in
                            swatch(choice)
                        }
                    }
                }

                // Named rather than shown as a switch: three genuinely different looks, and
                // "off" would imply glass is the app and the rest is its absence.
                Picker("Surfaces", selection: $preferences.surfaceStyle) {
                    ForEach(SurfaceStyle.allCases) { Text($0.label).tag($0) }
                }

                Picker("Open on", selection: $preferences.launchSurface) {
                    ForEach(LaunchSurface.allCases) { Text($0.label).tag($0) }
                }

                Toggle("Menu bar only", isOn: $preferences.menuBarOnly)
                    .onChange(of: preferences.menuBarOnly) { _, on in
                        // Applied immediately: a setting that needs a restart to mean
                        // anything is a setting the user cannot trust.
                        NSApp.setActivationPolicy(on ? .accessory : .regular)
                        if !on { NSApp.activate(ignoringOtherApps: true) }
                    }
            } footer: {
                Footnote(
                    preferences.surfaceStyle.detail
                        + " Reduce Transparency in System Settings overrides this and makes "
                        + "every surface solid. Menu bar only hides the Dock icon; Replay "
                        + "keeps recording either way."
                )
            }

            Section {
                LabeledContent("Welcome screen") {
                    Button("Show Welcome") { preferences.seenWelcome = false }
                }
            } footer: {
                Footnote("Shows the introduction again in the main window.")
            }

            Section {
                Toggle("Dock badge", isOn: $preferences.dockBadge)
                    .onChange(of: preferences.dockBadge) { _, on in
                        DockBadge.update(model, enabled: on)
                    }
            } footer: {
                Footnote(
                    "Today's active hours on the Dock icon, once there is an hour to show. "
                        + "A badge reading a few minutes is noise."
                )
            }

            Section {
                Picker("Drift in after", selection: $preferences.screensaverIdleMinutes) {
                    Text("Never").tag(0)
                    ForEach(Design.screensaverIdleChoices, id: \.self) { minutes in
                        Text("\(minutes) minutes").tag(minutes)
                    }
                }
                Toggle("Exit on mouse movement", isOn: $preferences.screensaverExitOnMouseMove)
                Toggle("Exit on click", isOn: $preferences.screensaverExitOnClick)
                Toggle("Exit on key press", isOn: $preferences.screensaverExitOnKey)
            } header: {
                Text("Screensaver")
            } footer: {
                Footnote(
                    "Drifts in only while Replay's own window is in front, so it never "
                        + "appears over another app. Escape and the close button always "
                        + "dismiss it, whatever these say."
                )
            }

            Section {
                Toggle("Daily recap", isOn: $preferences.dailySummary)
                    .onChange(of: preferences.dailySummary) { _, on in
                        Task { await enableNotification(on) }
                    }
                Picker("At", selection: $preferences.dailySummaryHour) {
                    ForEach(Design.notificationHours, id: \.self) { hour in
                        Text(Self.hourLabel(hour)).tag(hour)
                    }
                }
                .disabled(!preferences.dailySummary)
                .onChange(of: preferences.dailySummaryHour) { _, _ in
                    Task { await notifications.reschedule() }
                }

                Toggle("Weekly recap", isOn: $preferences.weeklyRecap)
                    .onChange(of: preferences.weeklyRecap) { _, on in
                        Task { await enableNotification(on) }
                    }
                Toggle("On this day", isOn: $preferences.onThisDayNotice)
                    .onChange(of: preferences.onThisDayNotice) { _, on in
                        Task { await enableNotification(on) }
                    }
            } header: {
                Text("Notifications")
            } footer: {
                Footnote(
                    notifications.permission == .denied
                        ? "macOS is not allowing Replay to notify. Turn it on in System "
                            + "Settings ▸ Notifications if you want these."
                        : "Written from your own history and handed to macOS already "
                            + "composed. Nothing is uploaded, and Replay asks for permission "
                            + "only when you switch one of these on."
                )
            }

            Section {
                Toggle("Surface memories on Today", isOn: $preferences.contextualMemories)
                    .onChange(of: preferences.contextualMemories) { _, _ in contextual.load() }

                // The threshold is the user's control over how often Replay speaks, so it is
                // named in words rather than shown as a number. "0.55" tells nobody anything.
                Picker("How sure Replay must be", selection: $preferences.memoryThreshold) {
                    ForEach(Design.memoryThresholds, id: \.self) { threshold in
                        Text(confidenceThresholdLabel(threshold)).tag(threshold)
                    }
                }
                .disabled(!preferences.contextualMemories)
                .onChange(of: preferences.memoryThreshold) { _, _ in contextual.load() }

                Toggle("Morning briefing", isOn: $preferences.morningBriefing)
                    .onChange(of: preferences.morningBriefing) { _, _ in contextual.load() }

                if !preferences.dismissedMemories.isEmpty {
                    LabeledContent("Put away") {
                        Button("Bring back \(preferences.dismissedMemories.count)") {
                            preferences.dismissedMemories = []
                            contextual.load()
                        }
                    }
                }
            } footer: {
                Footnote(
                    "Replay shows at most one memory a day, and most days it shows none. "
                        + "The briefing is a look back at yesterday, and it is gone by "
                        + "lunchtime. Everything either says is read from your own history "
                        + "on this Mac."
                )
            }

            Section {
                Picker("Daily goal", selection: goalSelection) {
                    Text("No goal").tag(0)
                    ForEach(Goals.presetMinutes, id: \.self) {
                        Text(Goals.format($0)).tag($0)
                    }
                    // A hand-set target stays selectable rather than snapping to the nearest
                    // preset the moment this list is opened.
                    if let goal = preferences.focusGoalMinutes, Goals.isCustom(goal) {
                        Text(Goals.format(goal)).tag(goal)
                    }
                }

                // Disabled with no goal set. Before, typing here silently *created* one —
                // a control that changed a setting it appeared unrelated to.
                LabeledContent("Custom target") {
                    HStack(spacing: Design.Space.snug) {
                        TextField("", value: customMinutes, format: .number)
                            .labelsHidden()
                            .frame(width: Design.Layout.numberField)
                            .multilineTextAlignment(.trailing)
                        Text("min").foregroundStyle(.secondary)
                    }
                }
                .disabled(!keepsGoal)
            } header: {
                Text("Focus goal")
            } footer: {
                Footnote(
                    keepsGoal
                        ? "Anything from \(Goals.format(Goals.minCustomMinutes)) to "
                            + "\(Goals.format(Goals.maxCustomMinutes))."
                        : "Off unless you ask for one. Replay describes your day; a goal you "
                            + "miss is never held against you."
                )
            }

            Section {
                Toggle("Activity tracking", isOn: Binding(
                    get: { model.isRecording },
                    set: { model.setTracking($0) }
                ))
            } header: {
                Text("Recording")
            } footer: {
                Footnote(
                    "Replay reads which app is frontmost through macOS's standard signal. It "
                        + "needs no Accessibility, Automation, or Screen Recording permission, "
                        + "and never looks inside your windows."
                )
            }
        }
    }
}

// ── privacy ───────────────────────────────────────────────────────────────────

private struct PrivacyTab: View {
    let model: AppModel
    let settings: SettingsModel
    @Bindable var preferences: Preferences

    @State private var managingExclusions = false

    var body: some View {
        PaneForm {
            Section {
                // The promise, stated once and plainly, before any control.
                Label {
                    VStack(alignment: .leading, spacing: Design.Space.tight) {
                        Text("Everything stays on this Mac")
                            .font(Design.Text.itemTitle)
                        Text(
                            "Replay records only which applications you use, and keeps it in "
                                + "one database in your own user folder. No cloud, no account, "
                                + "nothing to sign in to."
                        )
                        .font(Design.Text.detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(Design.Colour.assurance)
                        .font(.title2)
                }
            }

            if let info = settings.info {
                Section {
                    LabeledContent("Applications", value: "\(info.trackedApps)")
                    LabeledContent("Excluded", value: "\(info.excludedApps)")
                    LabeledContent("Events recorded", value: "\(info.eventCount)")
                    LabeledContent("On disk") {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(formatBytes(info.sizeBytes)).monospacedDigit()
                            Text(
                                info.reclaimableBytes > 0
                                    ? "at least \(formatBytes(info.reclaimableBytes)) reclaimable"
                                    : "all in use"
                            )
                            .font(Design.Text.micro)
                            .foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Text("What is stored")
                } footer: {
                    // The path, so "local" is verifiable rather than claimed.
                    Text(info.path)
                        .font(Design.Text.micro)
                        .monospaced()
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Section {
                LabeledContent("Excluded applications") {
                    Button(
                        preferences.excludedApps.isEmpty
                            ? "Manage…" : "\(preferences.excludedApps.count) excluded…"
                    ) { managingExclusions = true }
                }
                StatusFooter(settings: settings)
            } footer: {
                Footnote("Excluding an app also erases the history it already has.")
            }
        }
        .sheet(isPresented: $managingExclusions) {
            ExclusionsSheet(settings: settings, preferences: preferences)
        }
    }
}

/// Choosing what Replay must never see.
private struct ExclusionsSheet: View {
    let settings: SettingsModel
    @Bindable var preferences: Preferences
    @Environment(\.dismiss) private var dismiss

    @State private var pendingExclusion: KnownApp?
    @State private var search = ""

    private var shown: [KnownApp] {
        let all = settings.exclusionCandidates
        guard !search.isEmpty else { return all }
        return all.filter { $0.applicationName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(shown, id: \.bundleIdentifier) { app in
                    let excluded = preferences.excludedBundleIDs.contains(app.bundleIdentifier)
                    Toggle(isOn: Binding(
                        get: { excluded },
                        set: { on in
                            // Excluding erases history, so it asks first. Removing an
                            // exclusion takes nothing away and does not need to.
                            if on { pendingExclusion = app } else { settings.setExcluded(app, false) }
                        }
                    )) {
                        Label {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(app.applicationName)
                                Text(app.bundleIdentifier)
                                    .font(Design.Text.micro)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        } icon: {
                            AppIcon(
                                bundleID: app.bundleIdentifier,
                                appPath: app.appPath,
                                size: Design.Icon.listItem
                            )
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search applications")
            .overlay {
                if shown.isEmpty {
                    ContentUnavailableView(
                        search.isEmpty ? "No applications recorded yet" : "No matches",
                        systemImage: "magnifyingglass"
                    )
                }
            }

            Divider()
            HStack {
                StatusFooter(settings: settings)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(Design.Space.card)
        }
        .frame(width: Design.Layout.sheetWidth, height: Design.Layout.sheetHeight)
        .alert(
            "Exclude \(pendingExclusion?.applicationName ?? "this app")?",
            isPresented: Binding(
                get: { pendingExclusion != nil },
                set: { if !$0 { pendingExclusion = nil } }
            )
        ) {
            Button("Exclude and Erase", role: .destructive) {
                if let app = pendingExclusion { settings.setExcluded(app, true) }
                pendingExclusion = nil
            }
            Button("Cancel", role: .cancel) { pendingExclusion = nil }
        } message: {
            Text(
                "Replay will stop recording it and permanently erase everything already "
                    + "recorded for it. Un-excluding later resumes recording but cannot bring "
                    + "that history back."
            )
        }
    }
}

// ── data ──────────────────────────────────────────────────────────────────────

private struct DataTab: View {
    let settings: SettingsModel
    let export: ExportModel
    @Bindable var preferences: Preferences

    @State private var confirmingClear = false
    @State private var scope: Report.Scope = .week
    @State private var format: Report.Format = .markdown

    private var matching: Int { export.count(scope) }

    var body: some View {
        PaneForm {
            Section {
                LabeledContent("Report") {
                    HStack(spacing: Design.Space.snug) {
                        Picker("Scope", selection: $scope) {
                            ForEach(Report.Scope.allCases, id: \.self) {
                                Text($0.label).tag($0)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()

                        Picker("Format", selection: $format) {
                            ForEach(Report.Format.allCases, id: \.self) {
                                Text($0.label).tag($0)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()

                        Button("Export…") { export.exportScope(format, scope: scope) }
                            .disabled(matching == 0)
                    }
                }

                LabeledContent("Full backup") {
                    HStack(spacing: Design.Space.inline) {
                        Button("Export…") { export.exportBackup() }
                        Button("Import…") { export.importBackup() }
                    }
                }

                StatusFooter(export: export)
            } header: {
                Text("Your data")
            } footer: {
                // Said before the save panel rather than after: an export that turns out to
                // be empty is a wasted trip through a file dialog.
                Text(
                    "\(matching == 1 ? "1 session" : "\(matching) sessions") in \(scope.label). "
                        + "A backup restores; a report is for reading."
                )
            }

            Section {
                Picker("Keep activity for", selection: $preferences.retentionDays) {
                    ForEach(Preferences.retentionOptions, id: \.self) {
                        Text(Preferences.retentionLabel($0)).tag($0)
                    }
                }
                .onChange(of: preferences.retentionDays) { _, _ in settings.applyRetention() }

                LabeledContent("Compact database") {
                    Button(settings.busy ? "Compacting…" : "Compact") { settings.compact() }
                        .disabled(settings.busy)
                }

                StatusFooter(settings: settings)
            } header: {
                Text("Storage")
            } footer: {
                Footnote(compactFooter)
            }

            Section {
                LabeledContent("Activity history") {
                    Button("Clear History…", role: .destructive) { confirmingClear = true }
                }
            } footer: {
                Footnote("Deletes every event, headline, note and bookmark. There is no undo.")
            }
        }
        .alert("Clear activity history?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { settings.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This permanently deletes every recorded event from this Mac, along with every "
                    + "headline, note and bookmark. This can't be undone."
            )
        }
    }

    /// Deliberately different when there is nothing to reclaim: "at least" is the honest
    /// word for a freelist figure, and a compaction still repacks partly-filled pages.
    private var compactFooter: String {
        let keep = "Older raw events are removed past this window; day-by-day headlines are "
            + "kept either way. "
        guard let info = settings.info else { return keep }
        if info.reclaimableBytes > 0 {
            return keep + "At least \(formatBytes(info.reclaimableBytes)) would come back from "
                + "a compaction. A copy is taken first and checked before it is removed."
        }
        return keep + "Every page is holding live data, so there is little to recover — "
            + "compaction has real work to do after you delete history."
    }
}

// ── guide and about ───────────────────────────────────────────────────────────

private struct GuideTab: View {
    @Environment(\.motion) private var motion
    /// Which questions are open. A set rather than one selection: answering one question
    /// should not close the one you were half-way through reading.
    @State private var opened: Set<String> = []

    var body: some View {
        PaneForm {
            Section {
                ForEach(Guide.entries) { entry in
                    // Disclosure rather than four paragraphs: the questions stay scannable,
                    // and only the one being asked takes up room.
                    //
                    // Driven by a binding rather than left to `DisclosureGroup` so the whole
                    // row can open it. On its own it hands only the little triangle a hit
                    // area, which makes a full-width question into an eight-point target and
                    // leaves the obvious thing to click — the question — doing nothing.
                    DisclosureGroup(isExpanded: isOpen(entry)) {
                        Text(entry.answer)
                            .font(Design.Text.detail)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        // A `Button` rather than `onTapGesture`, so the row is reachable by
                        // Tab and announced as something that can be opened. A tap gesture
                        // would look identical and be invisible to the keyboard.
                        Button {
                            withAnimation(motion.animation(Design.Motion.inPlace)) {
                                toggle(entry)
                            }
                        } label: {
                            Text(entry.question)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(
                            opened.contains(entry.id) ? [.isButton, .isSelected] : .isButton
                        )
                        .accessibilityHint(opened.contains(entry.id) ? "Closes the answer" : "Opens the answer")
                    }
                }
            } header: {
                Text("How Replay works")
            }
        }
    }

    private func isOpen(_ entry: Guide.Entry) -> Binding<Bool> {
        Binding(
            get: { opened.contains(entry.id) },
            set: { wanted in
                if wanted { opened.insert(entry.id) } else { opened.remove(entry.id) }
            }
        )
    }

    private func toggle(_ entry: Guide.Entry) {
        if opened.contains(entry.id) { opened.remove(entry.id) } else { opened.insert(entry.id) }
    }
}

private struct AboutTab: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    var body: some View {
        VStack(spacing: Design.Space.snug) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: Design.Icon.about, height: Design.Icon.about)
            Text("Replay").font(.title2.weight(.semibold))
            Text("Version \(version)")
                .font(Design.Text.detail)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text("A private timeline of the apps you use. Everything stays on this Mac.")
                .font(Design.Text.detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Design.Space.tight)
        }
        .padding(Design.Space.page)
        .frame(minWidth: Design.Layout.settingsDetailWidth)
        .frame(maxHeight: .infinity)
    }
}

// ── shortcuts ─────────────────────────────────────────────────────────────────

/// Every key Replay binds, in one place — and now the *same* place the app binds them from.
///
/// This table used to be written out by hand beside an `NSMenu` that was also written out by
/// hand, with nothing able to compare them. It renders `Shortcuts` now, which the View menu
/// is built from, so a key cannot be changed in one and not the other. What a menu cannot
/// bind — the shortcuts that live on SwiftUI views — is declared there too and checked
/// against the sources by `tools/shortcut-audit.mjs`.
private struct ShortcutsTab: View {
    var body: some View {
        PaneForm {
            ForEach(Shortcuts.settingsGroups, id: \.0) { group, rows in
                Section(group.rawValue) {
                    ForEach(rows, id: \.label) { row in
                        LabeledContent(row.label) {
                            HStack(spacing: Design.Space.tight) {
                                ForEach(row.display, id: \.self) { key in
                                    Text(key)
                                        .font(Design.Text.detail)
                                        .padding(.horizontal, Design.Pill.countHorizontal)
                                        .padding(.vertical, Design.Pill.countVertical)
                                        .background(
                                            RoundedRectangle(
                                                cornerRadius: Design.Radius.small,
                                                style: .continuous
                                            )
                                            .fill(Design.Colour.fill)
                                        )
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(row.display.joined(separator: " "))
                        }
                    }
                }
            }
        }
    }
}
