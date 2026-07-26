import ReplayCore
import SwiftUI

/// Settings, in the tabs a Mac app puts them in.
///
/// Only what this port can actually honour: a control for a feature that is not built is a
/// promise the app breaks. The reference has Shortcuts, digests, and the memory subsystems
/// alongside these; they arrive with the features, not before them.
struct SettingsView: View {
    let model: AppModel
    let settings: SettingsModel
    let export: ExportModel
    @Bindable var preferences: Preferences

    var body: some View {
        TabView {
            GeneralTab(model: model, preferences: preferences)
                .tabItem { Label("General", systemImage: "gearshape") }
            PrivacyTab(model: model, settings: settings, preferences: preferences)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            DataTab(settings: settings, export: export, preferences: preferences)
                .tabItem { Label("Data", systemImage: "internaldrive") }
            GuideTab()
                .tabItem { Label("Guide", systemImage: "questionmark.circle") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 460)
        .onAppear { settings.reload() }
    }
}

// ── shared furniture ──────────────────────────────────────────────────────────

/// A labelled row with its explanation under it, and its control on the right.
private struct Row<Control: View>: View {
    let label: String
    var description: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.body)
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            control.fixedSize()
        }
        .padding(.vertical, 4)
    }
}

private struct Section<Content: View>: View {
    var title: String?
    var description: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.6)
            }
            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
    }
}

private struct TabScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// What an action just did, next to the control that ran it.
private struct StatusLine: View {
    let settings: SettingsModel

    var body: some View {
        if let error = settings.errorMessage {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        } else if let status = settings.status {
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The same, for the export model — which owns its own outcome because it runs a file
/// dialog the settings model knows nothing about.
private struct ExportStatusLine: View {
    let export: ExportModel

    var body: some View {
        if let error = export.errorMessage {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        } else if let status = export.status {
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// ── general ───────────────────────────────────────────────────────────────────

private struct GeneralTab: View {
    let model: AppModel
    @Bindable var preferences: Preferences

    /// Zero is how "no goal" is spelled in the picker; `nil` is how it is stored.
    private var goalSelection: Binding<Int> {
        Binding(
            get: { preferences.focusGoalMinutes ?? 0 },
            set: { preferences.focusGoalMinutes = $0 == 0 ? nil : $0 }
        )
    }

    /// Clamped on the way in, so a typed target cannot be set outside the bounds the
    /// reference enforces — 4 minutes or 40 hours is not a daily focus goal.
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

    var body: some View {
        TabScroll {
            Section(title: "Appearance") {
                Picker("Theme", selection: $preferences.appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            Divider()

            Section(title: "Window") {
                Row(label: "Open on", description: "Which surface the window shows when it opens.") {
                    Picker("Open on", selection: $preferences.launchSurface) {
                        ForEach(LaunchSurface.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                }

                Row(
                    label: "Menu bar only",
                    description: "Hide the Dock icon and live in the menu bar. Replay keeps "
                        + "recording either way."
                ) {
                    Toggle("", isOn: $preferences.menuBarOnly)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: preferences.menuBarOnly) { _, on in
                            // Applied immediately: a setting that needs a restart to mean
                            // anything is a setting the user cannot trust.
                            NSApp.setActivationPolicy(on ? .accessory : .regular)
                            if !on { NSApp.activate(ignoringOtherApps: true) }
                        }
                }
            }

            Divider()

            Section(
                title: "Focus goal",
                description: "A daily target you set for yourself. Off unless you ask for one — "
                    + "Replay describes your day, it doesn't set quotas, and a goal you miss is "
                    + "never held against you."
            ) {
                Row(label: "Daily goal") {
                    Picker("Daily goal", selection: goalSelection) {
                        Text("No goal").tag(0)
                        ForEach(Goals.presetMinutes, id: \.self) {
                            Text(Goals.format($0)).tag($0)
                        }
                        // A hand-set target stays selectable rather than snapping to the
                        // nearest preset the moment this list is opened.
                        if let goal = preferences.focusGoalMinutes, Goals.isCustom(goal) {
                            Text("\(Goals.format(goal)) (custom)").tag(goal)
                        }
                    }
                    .labelsHidden()
                }

                Row(
                    label: "Custom target",
                    description: "Anything from \(Goals.format(Goals.minCustomMinutes)) to "
                        + "\(Goals.format(Goals.maxCustomMinutes)), for a target that isn't a "
                        + "round hour."
                ) {
                    HStack(spacing: 6) {
                        TextField("", value: customMinutes, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                        Text("min").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            Section(
                title: "Recording",
                description: "Replay reads which app is frontmost through macOS's standard signal. "
                    + "It needs no Accessibility, Automation, or Screen Recording permission to do "
                    + "it, and never looks inside your windows."
            ) {
                Row(
                    label: "Activity tracking",
                    description: "Observe which apps you use to build your private timeline."
                ) {
                    Toggle("", isOn: Binding(
                        get: { model.isRecording },
                        set: { model.setTracking($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
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
        TabScroll {
            // The promise, stated once and plainly, before any control.
            VStack(alignment: .leading, spacing: 6) {
                Label("Everything stays on this Mac", systemImage: "checkmark.shield")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.green)
                Text(
                    "Replay records only which applications you use, and keeps it in one database "
                        + "in your own user folder. No cloud, no account, nothing to sign in to — "
                        + "your day never leaves this computer."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))

            // What is actually on disk, so "local" is verifiable rather than claimed.
            if let info = settings.info {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 0) {
                        Stat(label: "Tracked", value: "\(info.trackedApps)")
                        Stat(label: "Excluded", value: "\(info.excludedApps)")
                        Stat(label: "Events", value: "\(info.eventCount)")
                        // The size invites "why doesn't that go down?", so it carries its
                        // own answer.
                        Stat(
                            label: "On disk",
                            value: formatBytes(info.sizeBytes),
                            note: info.reclaimableBytes > 0
                                ? "at least \(formatBytes(info.reclaimableBytes)) reclaimable"
                                : "all in use"
                        )
                    }
                    Divider()
                    HStack(spacing: 6) {
                        Image(systemName: "internaldrive").font(.caption2).foregroundStyle(.tertiary)
                        Text(info.path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .truncationMode(.middle)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary.opacity(0.5), lineWidth: 1)
                )
            }

            Section(title: "Tracking") {
                Row(
                    label: "Excluded applications",
                    description: "Apps Replay should never record. Excluding one also erases its history."
                ) {
                    Button(
                        preferences.excludedApps.isEmpty
                            ? "Manage…" : "\(preferences.excludedApps.count) excluded…"
                    ) { managingExclusions = true }
                }
            }

            StatusLine(settings: settings)
        }
        .sheet(isPresented: $managingExclusions) {
            ExclusionsSheet(settings: settings, preferences: preferences)
        }
    }

    private struct Stat: View {
        let label: String
        let value: String
        var note: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .kerning(0.5)
                    .textCase(.uppercase)
                Text(value).font(.callout.weight(.medium)).monospacedDigit()
                if let note {
                    Text(note).font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Choosing what Replay must never see.
private struct ExclusionsSheet: View {
    let settings: SettingsModel
    @Bindable var preferences: Preferences
    @Environment(\.dismiss) private var dismiss

    @State private var pendingExclusion: KnownApp?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Excluded applications").font(.headline)
                Text(
                    "Replay never records an excluded app. Excluding one also erases what it "
                        + "already recorded — that cannot be undone by un-excluding it later."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)

            Divider()

            if settings.exclusionCandidates.isEmpty {
                Text("No applications recorded yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                List {
                    ForEach(settings.exclusionCandidates, id: \.bundleIdentifier) { app in
                        let excluded = preferences.excludedBundleIDs.contains(app.bundleIdentifier)
                        HStack(spacing: 10) {
                            AppIcon(bundleID: app.bundleIdentifier, appPath: app.appPath, size: 20)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(app.applicationName).font(.body)
                                Text(app.bundleIdentifier)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { excluded },
                                set: { on in
                                    // Excluding erases history, so it asks first. Removing an
                                    // exclusion takes nothing away and does not need to.
                                    if on { pendingExclusion = app } else { settings.setExcluded(app, false) }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                StatusLine(settings: settings)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 460, height: 420)
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
                "Replay will stop recording \(pendingExclusion?.applicationName ?? "it") and "
                    + "permanently erase everything it has already recorded for it. Un-excluding "
                    + "later resumes recording but cannot bring that history back."
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

    /// Recomputed as the scope changes, so the count on screen is about the scope on screen.
    private var matching: Int { export.count(scope) }

    var body: some View {
        TabScroll {
            Section(
                title: "Your data",
                description: "Your timeline is yours. Take a copy, or bring one back."
            ) {
                Row(
                    label: "Export report",
                    description: "Today, this week, this month, or everything you bookmarked or "
                        + "wrote a note on — as Markdown, CSV or JSON."
                ) {
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 6) {
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
                        // Said before the save panel rather than after: an export that turns
                        // out to be empty is a wasted trip through a file dialog.
                        Text(matching == 1 ? "1 session" : "\(matching) sessions")
                            .font(.caption)
                            .foregroundStyle(matching == 0 ? .secondary : .tertiary)
                            .monospacedDigit()
                    }
                }

                Row(
                    label: "Full backup",
                    description: "Every row as readable JSON — the format Replay can restore "
                        + "from. Importing merges; it never overwrites what is already here."
                ) {
                    HStack(spacing: 8) {
                        Button("Export…") { export.exportBackup() }
                        Button("Import…") { export.importBackup() }
                    }
                }
            }

            Divider()

            Section(
                title: "Storage",
                description: "Replay records no video and no screenshots — only which app was in "
                    + "front — so a heavy day costs a few hundred kilobytes."
            ) {
                Row(
                    label: "Keep activity for",
                    description: "Older raw events are removed past this window. Keeping everything "
                        + "never deletes a thing; your day-by-day headlines are kept either way, so "
                        + "history survives."
                ) {
                    Picker("Keep activity for", selection: $preferences.retentionDays) {
                        ForEach(Preferences.retentionOptions, id: \.self) {
                            Text(Preferences.retentionLabel($0)).tag($0)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: preferences.retentionDays) { _, _ in settings.applyRetention() }
                }

                Row(
                    label: "Compact database",
                    description: compactDescription
                ) {
                    Button(settings.busy ? "Compacting…" : "Compact") { settings.compact() }
                        .disabled(settings.busy)
                }
            }

            Divider()

            Section(
                title: "Danger zone",
                description: "There is no undo."
            ) {
                Row(
                    label: "Activity history",
                    description: "Permanently delete every event Replay has recorded on this Mac, "
                        + "along with its headlines, notes and bookmarks."
                ) {
                    Button("Clear History…", role: .destructive) { confirmingClear = true }
                }
            }

            StatusLine(settings: settings)
            ExportStatusLine(export: export)
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
    private var compactDescription: String {
        guard let info = settings.info else {
            return "Deleting history frees space inside the database file, but the file itself "
                + "doesn't shrink until it's rewritten."
        }
        if info.reclaimableBytes > 0 {
            return "Deleting history frees space inside the file without shrinking the file "
                + "itself. At least \(formatBytes(info.reclaimableBytes)) would come back. A copy "
                + "is taken first and the result checked before the copy is removed, so nothing "
                + "is at risk."
        }
        return "Every page here is holding live data, so there is little to recover — rewriting "
            + "may still pack it slightly tighter. This has real work to do after you delete "
            + "history, and Replay already does it on its own after a large deletion."
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
                + "and measures idle time from system input timing. It asks for no Accessibility, "
                + "Automation, or Screen Recording access — that is the point of it."
        ),
        Entry(
            question: "Where does my data go?",
            answer: "Into one SQLite file in your own user folder, named on the Privacy tab. "
                + "It is never uploaded anywhere."
        ),
        Entry(
            question: "What is a session?",
            answer: "A run of continuous work. Replay derives them from the recorded events "
                + "rather than storing them, so a gap of five minutes or more splits a run, and "
                + "one app holding focus for half an hour reads as absence rather than focus."
        ),
        Entry(
            question: "Why doesn't the file shrink when I delete history?",
            answer: "SQLite reuses freed pages instead of returning them, so the file stays the "
                + "same size until it is rewritten. Compact on the Data tab does that rewrite."
        ),
    ]

    var body: some View {
        TabScroll {
            Section(description: "How Replay works, in plain terms.") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.question).font(.body.weight(.medium))
                            Text(entry.answer)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

private struct AboutTab: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Replay").font(.title3.weight(.semibold))
            Text("Version \(version)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Text("A private timeline of the apps you use. Everything stays on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
