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
    let updates: UpdateModel
    let backups: AutoBackupModel

    /// The panes, in the order they are worth reaching for.
    /// Not private: the Help menu opens Settings on a chosen pane.
    enum Pane: String, CaseIterable, Identifiable, Hashable {
        case general = "General", privacy = "Privacy", data = "Data"
        // "Display" rather than "Tweaks" or "Addons": these are two whole features, not
        // optional extras or plugins, and the app already has a word for the pair — the
        // command palette groups the screensaver and ambient mode under Display, which is
        // the reference's own grouping. One word for one idea, wherever it appears.
        case display = "Display"
        case shortcuts = "Shortcuts", guide = "Guide", about = "About"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .privacy: "hand.raised"
            case .data: "internaldrive"
            case .display: "display"
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
            case .display: .orange
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
                        // `Loc.t`, for the same reason the main sidebar needs it: a pane's
                        // name is an enum's raw value, so no scan for literal text can see
                        // it, and this column stayed English in every language.
                        Text(Loc.t(item.rawValue))
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
                    PrivacyTab(
                        model: model, settings: settings, preferences: preferences,
                        notifications: notifications
                    )
                case .data:
                    DataTab(
                        settings: settings, export: export, preferences: preferences,
                        backups: backups
                    )
                case .display: DisplayTab(preferences: preferences)
                case .shortcuts: ShortcutsTab()
                case .guide: GuideTab()
                case .about: AboutTab(preferences: preferences, updates: updates)
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

extension View {
    /// The reference's own line under a control.
    ///
    /// A `Form` puts this where macOS puts it — under the row, secondary, wrapping to the
    /// content column. The port had 12 of these against the reference's 29, so most controls
    /// worked and said nothing about what they did.
    /// The same, for a row this port has and the reference does not. A separate entry
    /// point rather than an overload taking a protocol: the two lists are deliberately
    /// different things, and a call site should say which one it is reaching for.
    func explains(own row: OwnSettingsRow) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.hairline) {
            self
            Text(Loc.t(row.explanation))
                .font(Design.Text.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The same line, for the one row whose description depends on what it will do.
    ///
    /// Only "Auto-start when idle" uses this: it is the reference's row, and the reference's
    /// sentence describes the screensaver — which is only half true once the choice above it
    /// can point the same delay at ambient mode. The screensaver's wording still comes from
    /// ``SettingsRow`` rather than being restated here, so the contract keeps it honest.
    func explains(text: String) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.hairline) {
            self
            Text(Loc.t(text))
                .font(Design.Text.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func explains(_ row: SettingsRow) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.hairline) {
            self
            if let text = row.explanation.map(Loc.t) {
                Text(text)
                    .font(Design.Text.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// "6:00 PM" — a plain hour, in the locale's own clock.
///
/// Shared: the daily recap's hour and the span the displays are confined to are the same
/// question asked twice, and a second copy of this would be the place the two clocks quietly
/// stopped agreeing — one 24-hour, one not, on the same pane.
func hourLabel(_ hour: Int) -> String {
    var parts = DateComponents()
    parts.hour = hour
    parts.minute = 0
    guard let date = Calendar.current.date(from: parts) else { return "\(hour):00" }
    return date.formatted(.dateTime.hour().minute().locale(Loc.locale))
}

/// A language's name in its own language, which is how a language picker names languages.
///
/// "O‘zbekcha" rather than "Uzbek": somebody looking for their own language is looking for the
/// word they call it, and a list in English is only readable by people who did not need it.
func languageName(_ code: String) -> String {
    Locale(identifier: code).localizedString(forLanguageCode: code)?.capitalized(with: Locale(identifier: code))
        ?? code
}

/// A section's footnote, aligned the way the system aligns them.
///
/// `Form` centres a footer by default in this configuration, which reads as a caption for
/// the window rather than a note about the section above it.
private struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        // Translated here, and callers that compose a footnote out of parts translate the
        // parts instead — a lookup of an already-joined string asks the table for a sentence
        // nobody wrote.
        Text(Loc.t(text))
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
                Picker(SettingsRow.theme.label, selection: $preferences.appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                .horizontalRadioGroupLayout()
                    .explains(.theme)

                // Swatches rather than a list of colour names, because the choice is the
                // colour: reading "Pink" and picking it from a menu is a slower way to do
                // what looking at a row of dots does at a glance. "Match System" leads,
                // because following the accent already chosen in System Settings is the
                // right default and the row should say so.
                LabeledContent(Loc.t("Theme colour")) {
                    HStack(spacing: Design.Space.snug) {
                        ForEach(ThemeColour.allCases) { choice in
                            swatch(choice)
                        }
                    }
                }

                // Named rather than shown as a switch: three genuinely different looks, and
                // "off" would imply glass is the app and the rest is its absence.
                Picker(Loc.t("Surfaces"), selection: $preferences.surfaceStyle) {
                    ForEach(SurfaceStyle.allCases) { Text($0.label).tag($0) }
                }

                // Only the languages this build actually carries, plus the system. A picker
                // offering a language that resolves to nothing would be a promise the app
                // cannot keep — see `Loc.available`.
                Picker(OwnSettingsRow.language.label, selection: $preferences.languageCode) {
                    Text(Loc.t("Match System")).tag("")
                    ForEach(Loc.available.filter { $0 != "Base" }, id: \.self) { code in
                        Text(languageName(code)).tag(code)
                    }
                }
                .explains(own: .language)
                Picker(SettingsRow.openTo.label, selection: $preferences.launchSurface) {
                    ForEach(LaunchSurface.allCases) { Text($0.label).tag($0) }
                }
                    .explains(.openTo)

                Toggle(SettingsRow.menuBarMode.label, isOn: $preferences.menuBarOnly)
                    .explains(.menuBarMode)
                    .onChange(of: preferences.menuBarOnly) { _, on in
                        // Applied immediately: a setting that needs a restart to mean
                        // anything is a setting the user cannot trust.
                        NSApp.setActivationPolicy(on ? .accessory : .regular)
                        if !on { NSApp.activate(ignoringOtherApps: true) }
                    }
            } footer: {
                // Two sentences, looked up separately and joined after. Concatenating first
                // and looking up the result asked the table for a hybrid — half Uzbek, half
                // English — which matched nothing and rendered exactly that way. A key has to
                // be a whole sentence *and* a sentence has to be a whole key.
                Footnote(
                    preferences.surfaceStyle.detail + " "
                        + Loc.t(
                            "Reduce Transparency in System Settings overrides this and makes "
                                + "every surface solid."
                        )
                )
            }

            Section {
                LabeledContent(Loc.t("Welcome screen")) {
                    Button(Loc.t("Show Welcome")) { preferences.seenWelcome = false }
                }
            } footer: {
            }

            Section {
                Toggle(SettingsRow.dockBadge.label, isOn: $preferences.dockBadge)
                    .explains(.dockBadge)
                    .onChange(of: preferences.dockBadge) { _, on in
                        DockBadge.update(model, enabled: on)
                    }
            } footer: {
            }

            Section {
                Toggle(SettingsRow.dailySummary.label, isOn: $preferences.dailySummary)
                    .explains(.dailySummary)
                    .onChange(of: preferences.dailySummary) { _, on in
                        Task { await enableNotification(on) }
                    }
                Picker(Loc.t("At"), selection: $preferences.dailySummaryHour) {
                    ForEach(Design.notificationHours, id: \.self) { hour in
                        Text(hourLabel(hour)).tag(hour)
                    }
                }
                .disabled(!preferences.dailySummary)
                .onChange(of: preferences.dailySummaryHour) { _, _ in
                    Task { await notifications.reschedule() }
                }

                Toggle(SettingsRow.weeklyRecap.label, isOn: $preferences.weeklyRecap)
                    .explains(.weeklyRecap)
                    .onChange(of: preferences.weeklyRecap) { _, on in
                        Task { await enableNotification(on) }
                    }
                Toggle(SettingsRow.onThisDay.label, isOn: $preferences.onThisDayNotice)
                    .explains(.onThisDay)
                    .onChange(of: preferences.onThisDayNotice) { _, on in
                        Task { await enableNotification(on) }
                    }
            } header: {
                Text(Loc.t("Notifications"))
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
                // Two switches, not one. This is looking back at all — the same date in
                // earlier years, on Today and as its own surface. The one below is the
                // quieter thing that speaks when something becomes relevant, and they are
                // independent: someone can want their own history and not want to be spoken
                // to about it.
                Toggle(SettingsRow.todayInHistory.label, isOn: $preferences.todayInHistory)
                    .explains(.todayInHistory)

                Toggle(SettingsRow.surfaceMemories.label, isOn: $preferences.contextualMemories)
                    .explains(.surfaceMemories)
                    .onChange(of: preferences.contextualMemories) { _, _ in contextual.load() }

                // The threshold is the user's control over how often Replay speaks, so it is
                // named in words rather than shown as a number. "0.55" tells nobody anything.
                Picker(SettingsRow.howOftenToSpeak.label, selection: $preferences.memoryThreshold) {
                    ForEach(Design.memoryThresholds, id: \.self) { threshold in
                        Text(confidenceThresholdLabel(threshold)).tag(threshold)
                    }
                }
                .disabled(!preferences.contextualMemories)
                .onChange(of: preferences.memoryThreshold) { _, _ in contextual.load() }
                    .explains(.howOftenToSpeak)

                Toggle(SettingsRow.morningBriefing.label, isOn: $preferences.morningBriefing)
                    .explains(.morningBriefing)
                    .onChange(of: preferences.morningBriefing) { _, _ in contextual.load() }

                if !preferences.dismissedMemories.isEmpty {
                    LabeledContent(Loc.t("Put away")) {
                        Button(String(format: Loc.t("Bring back %@"), "\(preferences.dismissedMemories.count)")) {
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
                Picker(SettingsRow.dailyFocus.label, selection: goalSelection) {
                    Text(Loc.t("No goal")).tag(0)
                    ForEach(Goals.presetMinutes, id: \.self) {
                        Text(Goals.format($0)).tag($0)
                    }
                    // A hand-set target stays selectable rather than snapping to the nearest
                    // preset the moment this list is opened.
                    if let goal = preferences.focusGoalMinutes, Goals.isCustom(goal) {
                        Text(Goals.format(goal)).tag(goal)
                    }
                }
                    .explains(.dailyFocus)

                // Disabled with no goal set. Before, typing here silently *created* one —
                // a control that changed a setting it appeared unrelated to.
                LabeledContent(SettingsRow.customTarget.label) {
                    HStack(spacing: Design.Space.snug) {
                        TextField("", value: customMinutes, format: .number)
                            .labelsHidden()
                            .frame(width: Design.Layout.numberField)
                            .multilineTextAlignment(.trailing)
                        Text(Loc.t("min")).foregroundStyle(.secondary)
                    }
                }
                .disabled(!keepsGoal)
            } header: {
                Text(Loc.t("Focus goal"))
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
                Toggle(SettingsRow.activityTracking.label, isOn: Binding(
                    get: { model.isRecording },
                    set: { recording in
                        // Turning it back on here ends a timed pause too, for the same reason
                        // the menu bar's does: the pause is over because somebody said so.
                        preferences.pausedUntil = recording ? nil : preferences.pausedUntil
                        model.setTracking(recording)
                    }
                ))
                    .explains(.activityTracking)
                // Only while a pause has an end. An indefinite one is visible in the switch
                // itself, and a line repeating what the switch says is furniture.
                if !model.isRecording, let until = preferences.pausedUntil {
                    Text(String(
                        format: Loc.t("Recording resumes at %@."),
                        until.formatted(.dateTime.hour().minute().locale(Loc.locale))
                    ))
                    .font(Design.Text.detail)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text(Loc.t("Recording"))
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
    /// The one permission Replay ever asks for, so Privacy can state where it stands.
    let notifications: NotificationsModel

    @State private var managingExclusions = false

    private var notificationState: String {
        switch notifications.permission {
        case .granted: "Allowed"
        case .denied: "Not allowed"
        case .unknown: "Not asked yet"
        }
    }

    private var notificationGlyph: String {
        switch notifications.permission {
        case .granted: "checkmark.circle.fill"
        case .denied: "exclamationmark.triangle.fill"
        case .unknown: "circle.dashed"
        }
    }

    private var notificationTint: Color {
        switch notifications.permission {
        case .granted: Design.Colour.assurance
        case .denied: .orange
        case .unknown: .secondary
        }
    }


    var body: some View {
        PaneForm {
            Section {
                // The promise, stated once and plainly, before any control.
                Label {
                    VStack(alignment: .leading, spacing: Design.Space.tight) {
                        Text(Loc.t("Everything stays on this Mac"))
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

            // Notifications: the only permission Replay ever asks for, and the only one worth
            // a row. Everything above this section works without asking anybody anything —
            // that is the product, not a feature — so a "Permissions" list would be one real
            // entry padded out with reassurances, and would imply the app is waiting on
            // something it is not. A denied state is otherwise invisible: the recaps simply
            // never arrive and nothing says why.
            Section {
                LabeledContent(Loc.t("Notifications")) {
                    HStack(spacing: Design.Space.snug) {
                        Image(systemName: notificationGlyph)
                            .foregroundStyle(notificationTint)
                        Text(notificationState)
                            .foregroundStyle(.secondary)
                        if notifications.permission == .denied {
                            Button(Loc.t("Open Settings…")) {
                                NSWorkspace.shared.open(
                                    URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
                                )
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
            } header: {
                Text(Loc.t("Permission"))
            } footer: {
                Footnote(
                    notifications.permission == .denied
                        ? "The daily and weekly recaps need this. Everything else in Replay "
                            + "works without it."
                        : "Only the recaps use this. Replay records, remembers and shows your "
                            + "history whether or not it is granted."
                )
            }
            .task { await notifications.refreshPermission() }

            if let info = settings.info {
                Section {
                    LabeledContent(SettingsRow.tracked.label, value: "\(info.trackedApps)")
                    LabeledContent(SettingsRow.excluded.label, value: "\(info.excludedApps)")
                    LabeledContent(SettingsRow.events.label, value: "\(info.eventCount)")
                    LabeledContent(SettingsRow.onDisk.label) {
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
                    Text(Loc.t("What is stored"))
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
                LabeledContent(Loc.t("Excluded applications")) {
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
                Button(Loc.t("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
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
            Button(Loc.t("Exclude and Erase"), role: .destructive) {
                if let app = pendingExclusion { settings.setExcluded(app, true) }
                pendingExclusion = nil
            }
            Button(Loc.t("Cancel"), role: .cancel) { pendingExclusion = nil }
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
    let backups: AutoBackupModel

    @State private var confirmingClear = false
    @State private var confirmingReset = false
    @State private var confirmingDayDelete = false
    /// `0` is "none chosen", so the button beside it stays disabled until a day is picked.
    @State private var dayToDelete: Int64 = 0
    @State private var scope: Report.Scope = .week
    @State private var format: Report.Format = .markdown

    private var matching: Int { export.count(scope) }

    var body: some View {
        PaneForm {
            Section {
                LabeledContent(Loc.t("Report")) {
                    HStack(spacing: Design.Space.snug) {
                        Picker(Loc.t("Scope"), selection: $scope) {
                            ForEach(Report.Scope.allCases, id: \.self) {
                                Text($0.label).tag($0)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()

                        Picker(Loc.t("Format"), selection: $format) {
                            ForEach(Report.Format.allCases, id: \.self) {
                                Text($0.label).tag($0)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()

                        Button(Loc.t("Export…")) { export.exportScope(format, scope: scope) }
                            .disabled(matching == 0)
                    }
                }

                LabeledContent(Loc.t("Full backup")) {
                    HStack(spacing: Design.Space.inline) {
                        Button(Loc.t("Export…")) { export.exportBackup() }
                        Button(export.busy ? Loc.t("Importing…") : Loc.t("Import…")) {
                            Task { await export.importBackup() }
                        }
                        .disabled(export.busy)
                    }
                }
                .explains(.fullBackup)

                StatusFooter(export: export)
            } header: {
                Text(Loc.t("Your data"))
            } footer: {
                // Said before the save panel rather than after: an export that turns out to
                // be empty is a wasted trip through a file dialog.
                Text(
                    "\(matching == 1 ? "1 session" : "\(matching) sessions") in \(scope.label). "
                        + "A backup restores; a report is for reading."
                )
            }

            Section {
                Picker(
                    OwnSettingsRow.automaticBackup.label,
                    selection: $preferences.autoBackupCadence
                ) {
                    ForEach(AutoBackup.Cadence.allCases, id: \.self) { cadence in
                        Text(cadence.label).tag(cadence)
                    }
                }
                .explains(own: .automaticBackup)
                // Only once there is a schedule: a folder chosen for a backup that will never
                // be taken is a control that does nothing, and the pane already has enough
                // rows without one.
                if preferences.autoBackupCadence != .off {
                    LabeledContent(OwnSettingsRow.backupFolder.label) {
                        HStack(spacing: Design.Space.inline) {
                            Text(backups.folderLabel ?? Loc.t("None chosen"))
                                .foregroundStyle(
                                    backups.folderLabel == nil ? .secondary : .primary
                                )
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button(Loc.t("Choose…")) { backups.chooseFolder() }
                            Button(Loc.t("Back up now")) { backups.runNow() }
                                .disabled(backups.folderLabel == nil)
                        }
                    }
                    .explains(own: .backupFolder)
                }
                if let error = backups.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(Design.Text.detail)
                } else if let status = backups.status {
                    Text(status).foregroundStyle(.secondary).font(Design.Text.detail)
                }
            } header: {
                // Not "Automatic backup": that is the row's own name, and a section headed
                // with the same words as its first row reads as a stutter.
                Text(Loc.t("On a schedule"))
            } footer: {
                Footnote(
                    backups.lastRunLabel.map {
                        String(format: Loc.t("Last written %@."), $0)
                    } ?? Loc.t(
                        "Nothing has been written yet. Choosing a folder with a schedule set "
                            + "writes the first copy straight away, and the rest arrive "
                            + "while Replay is running — it is a background courtesy, not a "
                            + "daemon, so a Mac that was off has nothing to catch up."
                    )
                )
            }

            Section {
                Picker(SettingsRow.keepActivityFor.label, selection: $preferences.retentionDays) {
                    ForEach(Preferences.retentionOptions, id: \.self) {
                        Text(Preferences.retentionLabel($0)).tag($0)
                    }
                }
                .onChange(of: preferences.retentionDays) { _, _ in settings.applyRetention() }
                    .explains(.keepActivityFor)

                // A day at a time, between the retention rule that removes many and the
                // clear that removes everything. Reachable from the Timeline's ⋯ too, which
                // can reach *any* day — this one is bounded, because a picker is scrolled and
                // a list of every day Replay has seen is a worse way to find last Tuesday.
                LabeledContent(SettingsRow.deleteASingleDay.label) {
                    HStack(spacing: Design.Space.snug) {
                        Picker("", selection: $dayToDelete) {
                            Text(Loc.t("Choose a day")).tag(Int64(0))
                            ForEach(settings.deletableDays, id: \.dayStart) { day in
                                Text(day.label).tag(day.dayStart)
                            }
                        }
                        .labelsHidden()
                        Button(Loc.t("Delete…"), role: .destructive) { confirmingDayDelete = true }
                            .disabled(dayToDelete == 0)
                    }
                }
                .explains(.deleteASingleDay)

                LabeledContent(SettingsRow.compactDatabase.label) {
                    Button(settings.busy ? "Compacting…" : "Compact") {
                        Task { await settings.compact() }
                    }
                        .disabled(settings.busy)
                }

                StatusFooter(settings: settings)
            } header: {
                Text(Loc.t("Storage"))
            } footer: {
                Footnote(compactFooter)
            }

            Section {
                LabeledContent(Loc.t("Activity history")) {
                    Button(Loc.t("Clear History…"), role: .destructive) { confirmingClear = true }
                }
                LabeledContent(SettingsRow.resetReplay.label) {
                    Button(Loc.t("Reset…"), role: .destructive) { confirmingReset = true }
                }
                .explains(.resetReplay)
            } footer: {
                Footnote("Deletes every event, headline, note and bookmark. There is no undo.")
            }
        }
        .alert(Loc.t("Clear activity history?"), isPresented: $confirmingClear) {
            Button(Loc.t("Clear History"), role: .destructive) { settings.clearHistory() }
            Button(Loc.t("Cancel"), role: .cancel) {}
        } message: {
            Text(
                "This permanently deletes every recorded event from this Mac, along with every "
                    + "headline, note and bookmark. This can't be undone."
            )
        }
        // Both name what they will take before they take it (SPEC §8). The day dialog names
        // the day, because "delete a day" is only a safe thing to confirm if you can see
        // which one you picked.
        .alert(
            "Delete \(settings.deletableDays.first { $0.dayStart == dayToDelete }?.label ?? "this day")?",
            isPresented: $confirmingDayDelete
        ) {
            Button(Loc.t("Delete Day"), role: .destructive) {
                settings.deleteDay(dayToDelete)
                dayToDelete = 0
            }
            Button(Loc.t("Cancel"), role: .cancel) {}
        } message: {
            Text(
                "This takes that day's sessions, its summary, its reflection and anything you "
                    + "wrote about it. Every other day is untouched, and this can't be undone."
            )
        }
        .alert(Loc.t("Reset Replay?"), isPresented: $confirmingReset) {
            Button(Loc.t("Reset Replay"), role: .destructive) {
                settings.resetEverything(preferences: preferences)
            }
            Button(Loc.t("Cancel"), role: .cancel) {}
        } message: {
            Text(
                "This deletes all activity, every setting and every preference, and returns "
                    + "Replay to the welcome screen. This can't be undone."
            )
        }
    }

    /// Deliberately different when there is nothing to reclaim: "at least" is the honest
    /// word for a freelist figure, and a compaction still repacks partly-filled pages.
    /// What a compaction would actually reclaim.
    ///
    /// The retention sentence that used to open this has gone: "Keep activity for" now
    /// carries the reference's own line directly under it, and repeating it here said the
    /// same thing twice in two different wordings a few points apart.
    private var compactFooter: String {
        guard let info = settings.info else { return "" }
        if info.reclaimableBytes > 0 {
            return "At least \(formatBytes(info.reclaimableBytes)) would come back from a "
                + "compaction. A copy is taken first and checked before it is removed."
        }
        return "Every page is holding live data, so there is little to recover — compaction "
            + "has real work to do after you delete history."
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
                ForEach(Guide.entries + Guide.ownEntries) { entry in
                    // Disclosure rather than four paragraphs: the questions stay scannable,
                    // and only the one being asked takes up room.
                    //
                    // Driven by a binding rather than left to `DisclosureGroup` so the whole
                    // row can open it. On its own it hands only the little triangle a hit
                    // area, which makes a full-width question into an eight-point target and
                    // leaves the obvious thing to click — the question — doing nothing.
                    DisclosureGroup(isExpanded: isOpen(entry)) {
                        Text(Loc.t(entry.answer))
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
                            Text(Loc.t(entry.question))
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
                Text(Loc.t("How Replay works"))
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
    @Bindable var preferences: Preferences
    let updates: UpdateModel

    /// Where the source lives. In About because that is where somebody looks when they want
    /// to know what this *is* — and for an app whose whole claim is that nothing leaves the
    /// Mac, "you can read it" is the strongest form that claim takes.
    private static let repository = URL(string: "https://github.com/nurkamol/replay-swift")!

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? Replay.version
    }

    var body: some View {
        VStack(spacing: Design.Space.snug) {
            Image(nsImage: BundleIcon.image)
                .resizable()
                .frame(width: Design.Icon.about, height: Design.Icon.about)
            Text(Loc.t("Replay")).font(.title2.weight(.semibold))
            Text(String(format: Loc.t("Version %@"), "\(version)"))
                .font(Design.Text.detail)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(Loc.t("A private timeline of the apps you use. Everything stays on this Mac."))
                .font(Design.Text.detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Design.Space.tight)

            // The same window the Help menu opens. Here as well because About is where
            // somebody looks to find out what version they have, and "what changed in it" is
            // the next thing they want — the reference puts it in both places for that reason.
            Button {
                (NSApp.delegate as? AppDelegate)?.openWhatsNew()
            } label: {
                Label(Loc.t("What's New"), systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, Design.Space.inline)

            Link(destination: Self.repository) {
                Label(Loc.t("Source on GitHub"), systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .buttonStyle(.link)
            .padding(.top, Design.Space.tight)
            .help(Self.repository.absoluteString)

            // The one setting in the app that causes a network request, so it lives beside
            // the version it is about rather than buried in General — and it says what it
            // sends rather than only what it does.
            VStack(alignment: .leading, spacing: Design.Space.tight) {
                Toggle(
                    OwnSettingsRow.checkForUpdates.label, isOn: $preferences.checkForUpdates
                )
                .explains(own: .checkForUpdates)
                HStack(spacing: Design.Space.snug) {
                    Button(Loc.t("Check Now")) { Task { await updates.checkNow() } }
                        .disabled(updates.checking)
                    if updates.checking { ProgressView().controlSize(.small) }
                    if let failure = updates.failure {
                        Text(failure).font(Design.Text.detail).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, Design.Space.block)
            .frame(maxWidth: Design.Layout.readableWidth)

            Spacer(minLength: 0)
            Text(Loc.t("MIT licensed. Built on this Mac, and it stays here."))
                .font(Design.Text.micro)
                .foregroundStyle(.tertiary)
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
                        LabeledContent(Loc.t(row.label)) {
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

/// Display — the two surfaces that take the whole screen.
///
/// One pane rather than two sections buried in General, and named for what the pair *are*
/// rather than for how optional they feel. The command palette already groups them under
/// Display, following the reference; a settings tab called Tweaks or Addons would have said
/// these are extras, and they are two of the app's features.
///
/// The screensaver is for when you have gone. Ambient mode is for while you are here. They
/// are the only things in Replay that cover the menu bar, which is the whole reason they
/// belong together.
private struct DisplayTab: View {
    @Bindable var preferences: Preferences

    /// The screens attached right now, by the names the system gives them.
    ///
    /// Kept in state and refreshed on `didChangeScreenParameters` rather than read inside
    /// `body`: plugging a display in while Settings is open should add it to the list, and a
    /// view that reads `NSScreen.screens` as it draws only happens to be right.
    @State private var screens: [String] = NSScreen.screens.map(\.localizedName)

    /// The choices the picker offers: the keyboard's screen, every attached one, and — when
    /// the chosen screen is not here — the chosen one, so the setting still shows what it
    /// says rather than falling blank the moment a laptop is undocked.
    private var screenChoices: [String] {
        let chosen = preferences.displayScreenName
        return chosen.isEmpty || screens.contains(chosen) ? screens : screens + [chosen]
    }

    private func screenLabel(_ name: String) -> String {
        screens.contains(name)
            ? name
            : String(format: Loc.t("%@ (not connected)"), name)
    }

    var body: some View {
        Form {
            // Auto-start first, because it is the only thing on this pane that can happen
            // without being asked for a second time — everything below it is a detail of a
            // display you have already chosen to open.
            Section {
                Picker(
                    OwnSettingsRow.idleDisplay.label, selection: $preferences.idleDisplay
                ) {
                    ForEach(IdleDisplay.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .explains(own: .idleDisplay)
                Picker(
                    SettingsRow.autoStartWhenIdle.label,
                    selection: $preferences.screensaverIdleMinutes
                ) {
                    Text(Loc.t("Never")).tag(0)
                    ForEach(Design.idleStartChoices, id: \.self) { minutes in
                        Text(String(format: Loc.t("%@ minutes"), "\(minutes)")).tag(minutes)
                    }
                }
                // The line under this row says which display it will raise, because with
                // the choice above it the reference's own sentence is only true for one of
                // the two. The screensaver's wording still comes from the contract.
                .explains(text: preferences.idleDisplay.idleExplanation)
                Toggle(
                    OwnSettingsRow.idleHours.label, isOn: $preferences.idleHoursLimited
                )
                .explains(own: .idleHours)
                if preferences.idleHoursLimited {
                    Picker(Loc.t("From"), selection: $preferences.idleFromHour) {
                        ForEach(Design.hoursOfTheDay, id: \.self) { hour in
                            Text(hourLabel(hour)).tag(hour)
                        }
                    }
                    Picker(Loc.t("Until"), selection: $preferences.idleUntilHour) {
                        ForEach(Design.hoursOfTheDay, id: \.self) { hour in
                            Text(hourLabel(hour)).tag(hour)
                        }
                    }
                }
            } header: {
                Text(Loc.t("Auto-start"))
            } footer: {
                Footnote(
                    "Either drifts in only while Replay's own window is in front, so it "
                        + "never appears over another app. Never means neither does, and "
                        + "both can still be opened by hand from the sidebar, the View menu "
                        + "or ⌘K. What starts on its own leaves the way it came: any key, "
                        + "click or movement returns you — including in ambient mode, which "
                        + "stays put when you open it yourself, since that is the point of "
                        + "it."
                )
            }

            Section {
                Picker(
                    OwnSettingsRow.displayScreen.label,
                    selection: $preferences.displayScreenName
                ) {
                    Text(Loc.t("Wherever the keyboard is")).tag("")
                    ForEach(screenChoices, id: \.self) { name in
                        Text(screenLabel(name)).tag(name)
                    }
                }
                .explains(own: .displayScreen)
            } header: {
                Text(Loc.t("The screen"))
            }
            // A display plugged in or unplugged while this pane is open changes the answer,
            // and the picker is the one place in the app where that has to show immediately.
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSApplication.didChangeScreenParametersNotification
                )
            ) { _ in
                screens = NSScreen.screens.map(\.localizedName)
            }

            Section {
                Toggle(
                    SettingsRow.exitOnMouseMovement.label,
                    isOn: $preferences.screensaverExitOnMouseMove
                )
                .explains(.exitOnMouseMovement)
                Toggle(SettingsRow.exitOnClick.label, isOn: $preferences.screensaverExitOnClick)
                    .explains(.exitOnClick)
                Toggle(SettingsRow.exitOnKeyPress.label, isOn: $preferences.screensaverExitOnKey)
                    .explains(.exitOnKeyPress)
                Toggle(
                    OwnSettingsRow.screensaverClock.label, isOn: $preferences.screensaverClock
                )
                .explains(own: .screensaverClock)
            } header: {
                Text(Loc.t("Screensaver"))
            } footer: {
                Footnote(
                    "These three are the screensaver's own, and apply however it was "
                        + "started. Opening either of the two displays closes the other; "
                        + "they are never both up, and neither ever covers the one you are "
                        + "deliberately reading. Escape and the close button always dismiss "
                        + "whichever is up, whatever these say."
                )
            }

            Section {
                Toggle(
                    OwnSettingsRow.ambientStaysOpen.label,
                    isOn: $preferences.ambientStaysOpen
                )
                .explains(own: .ambientStaysOpen)
                Toggle(OwnSettingsRow.ambientClock.label, isOn: $preferences.ambientClock)
                    .explains(own: .ambientClock)
                Toggle(
                    OwnSettingsRow.ambientCurrentApp.label,
                    isOn: $preferences.ambientCurrentApp
                )
                .explains(own: .ambientCurrentApp)
                Toggle(
                    OwnSettingsRow.ambientCurrentSession.label,
                    isOn: $preferences.ambientCurrentSession
                )
                .explains(own: .ambientCurrentSession)
                Toggle(OwnSettingsRow.ambientBreath.label, isOn: $preferences.ambientBreath)
                    .explains(own: .ambientBreath)
            } header: {
                Text(Loc.t("Ambient mode"))
            } footer: {
                Footnote(
                    "The day's total is always shown — it is what the screen is for. These "
                        + "are the things around it, and two of them are here because an "
                        + "ambient screen is usually a second screen, and a second screen "
                        + "is often one other people can see. A screen left open takes no "
                        + "keyboard, so Escape does not reach it: close it with ⇧⌘A, the "
                        + "View menu, or the ✕ in its corner."
                )
            }
        }
        .formStyle(.grouped)
    }
}
