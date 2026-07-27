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

    /// The panes, in the order they are worth reaching for.
    private enum Pane: String, CaseIterable, Identifiable, Hashable {
        case general = "General", privacy = "Privacy", data = "Data"
        case guide = "Guide", about = "About"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .privacy: "hand.raised"
            case .data: "internaldrive"
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
            case .guide: .teal
            case .about: .secondary
            }
        }
    }

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
        } detail: {
            Group {
                switch pane {
                case .general: GeneralTab(model: model, preferences: preferences, contextual: contextual)
                case .privacy:
                    PrivacyTab(model: model, settings: settings, preferences: preferences)
                case .data: DataTab(settings: settings, export: export, preferences: preferences)
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

    var body: some View {
        PaneForm {
            Section {
                Picker("Appearance", selection: $preferences.appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                .horizontalRadioGroupLayout()

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
                Footnote("Menu bar only hides the Dock icon. Replay keeps recording either way.")
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
    private struct Entry: Identifiable {
        let question: String
        let answer: String
        var id: String { question }
    }

    private let entries: [Entry] = [
        Entry(
            question: "What does Replay record?",
            answer: "Which application is in front, and when you were away from the keyboard. "
                + "Nothing about what is inside a window — not titles, not text, not screenshots."
        ),
        Entry(
            question: "Does it need any permissions?",
            answer: "No. Replay reads the frontmost application through macOS's standard signal "
                + "and measures idle time from system input timing."
        ),
        Entry(
            question: "What is a session?",
            answer: "A run of continuous work, derived from the recorded events rather than "
                + "stored. A gap of five minutes or more splits a run, and one app holding "
                + "focus for half an hour reads as absence rather than focus."
        ),
        Entry(
            question: "Why doesn't the file shrink when I delete history?",
            answer: "SQLite reuses freed pages instead of returning them, so the file stays the "
                + "same size until it is rewritten. Compact, on the Data tab, does that."
        ),
    ]

    var body: some View {
        PaneForm {
            Section {
                ForEach(entries) { entry in
                    // Disclosure rather than four paragraphs: the questions stay scannable,
                    // and only the one being asked takes up room.
                    DisclosureGroup(entry.question) {
                        Text(entry.answer)
                            .font(Design.Text.detail)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } header: {
                Text("How Replay works")
            }
        }
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
