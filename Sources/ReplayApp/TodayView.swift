import ReplayCore
import SwiftUI

/// Today: the day's headline, then the day itself.
///
/// It describes rather than grades — no targets, no red, no scolding a quiet day. The
/// figures are large because they are the point; everything else is quiet around them.
struct TodayView: View {
    @Environment(\.motion) private var motion
    let model: AppModel
    let annotations: AnnotationsModel
    let export: ExportModel
    let memories: MemoriesModel
    @Bindable var preferences: Preferences
    /// Given so the card can lead somewhere rather than just informing.
    let onOpenDay: (Int64) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.block) {
                if let summary = model.summary, summary.switches > 0 {
                    HeadlineCard(summary: summary)
                    // Only when one has been asked for. No goal means no card, not an
                    // invitation to set one — the app does not push a target on anybody.
                    if let goal = preferences.focusGoalMinutes {
                        FocusGoalCard(
                            progress: Goals.progress(
                                activeSeconds: summary.activeSeconds, goalMinutes: goal
                            ),
                            streak: Goals.streak(
                                summaries: model.recentSummaries,
                                todayStart: startOfLocalDay(model.now),
                                todayActiveSeconds: summary.activeSeconds,
                                goalMinutes: goal
                            ),
                            goalMinutes: goal,
                            onSetGoal: { preferences.focusGoalMinutes = $0 }
                        )
                    }
                    reflection
                    // The nearest one only, and only when there is one. Today is about
                    // today; a gallery of the past belongs on its own surface.
                    if let memory = memories.memories.first {
                        TodayInHistoryCard(
                            memory: memory,
                            onOpen: { onOpenDay(memory.range.dayStart) }
                        )
                    }
                    sessionList
                } else {
                    quietDay.centredInPage()
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle("Today")
        .navigationSubtitle(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .onAppear { if !memories.loaded { memories.load() } }
    }


    private var quietDay: some View {
        ContentUnavailableView {
            Label("A quiet day", systemImage: "moon.stars")
        } description: {
            Text("Nothing recorded yet. Your sessions will appear here as you work.")
        }
    }

    private var reflection: some View {
        ReflectionCard(
            dayStart: startOfLocalDay(model.now),
            reflection: model.reflection,
            prompt: "What do you want to remember about today?",
            onCommit: { model.setReflection($0) }
        )
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text("\(model.sessions.count) \(model.sessions.count == 1 ? "session" : "sessions")")
                .font(Design.Text.sectionLabel)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(Design.Text.labelKerning)

            ForEach(Array(model.timeline.enumerated()), id: \.offset) { _, item in
                switch item {
                case .session(let session):
                    SessionCard(
                        session: session,
                        annotations: annotations,
                        export: export,
                        onDelete: { model.deleteSession(session) }
                    )
                    .settlesIntoView(reduced: motion.reduced)
                case .breakItem(let gap):
                    BreakRow(gap: gap)
                }
            }
        }
    }
}

/// The day in one glance: how long, across how much, and what dominated it.
private struct HeadlineCard: View {
    let summary: DaySummary
    @Environment(\.motion) private var motion

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.section) {
            VStack(alignment: .leading, spacing: 0) {
                Text(formatDurationShort(summary.activeSeconds))
                    .font(Design.Text.hero)
                    .monospacedDigit()
                    // The day's total re-derives every thirty seconds. A number that
                    // replaces itself is a flicker; one that rolls is the same number,
                    // still counting.
                    .contentTransition(.numericText())
                    .animation(motion.animation(Design.Motion.settle), value: summary.activeSeconds)
                    .accessibilityLabel("\(formatDurationShort(summary.activeSeconds)) active today")
                Text("active")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Design.Space.statGap) {
                Stat(value: "\(summary.appsUsed)", label: "applications")
                Stat(value: "\(summary.sessionCount)", label: "sessions")
                if let focus = summary.focus {
                    Stat(
                        value: formatDurationShort(focus.averageStretchSeconds),
                        label: "\(focus.quality.rawValue) focus"
                    )
                }
                if let longest = summary.longestSession {
                    Stat(value: formatDurationShort(longest.activeSeconds), label: "longest focus")
                }
            }

            if let top = summary.mostUsed {
                HStack(spacing: Design.Space.row) {
                    AppIcon(bundleID: top.bundleIdentifier, appPath: top.appPath, size: Design.Icon.feature)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("TOP APP")
                            .font(Design.Text.cardLabel)
                            .foregroundStyle(.tertiary)
                            .kerning(Design.Text.labelKerning)
                        Text(top.applicationName).font(Design.Text.figure)
                    }
                    Spacer()
                    Text(formatDurationShort(top.seconds))
                        .font(Design.Text.figure)
                        .monospacedDigit()
                }
                .padding(Design.Space.card)
                .background(Design.Colour.fill, in: RoundedRectangle(cornerRadius: Design.Radius.card))
            }
        }
        .padding(Design.Space.block)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Colour.surfaceRaised, in: RoundedRectangle(cornerRadius: Design.Radius.surface))
    }

    private struct Stat: View {
        let value: String
        let label: String
        var body: some View {
            HStack(spacing: Design.Space.snug) {
                Text(value).font(.callout.weight(.semibold)).monospacedDigit()
                Text(label).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

/// One run of work: its apps, its name, its length — expandable to the breakdown.
///
/// Shared by Today, the Timeline, and a reopened day: a session reads the same wherever it
/// is found, which is the whole point of building it from the same derivation.
struct SessionCard: View {
    let session: ActivitySession
    let annotations: AnnotationsModel
    let export: ExportModel
    let onDelete: () -> Void

    @State private var expanded = false
    @Environment(\.motion) private var motion

    private var annotation: SessionAnnotation { annotations.annotation(for: session.startedAt) }

    /// One sentence, because VoiceOver reads a card as a sentence rather than as the six
    /// fragments it is laid out from. Marks are named, since their meaning is carried by
    /// colour and shape on screen.
    private var accessibilityDescription: String {
        var parts = [
            session.title,
            formatRange(session.startedAt, session.endedAt),
            "\(formatDurationShort(session.activeSeconds)) active",
            "\(session.apps.count) \(session.apps.count == 1 ? "app" : "apps")",
        ]
        if annotation.bookmarked { parts.append("bookmarked") }
        if !annotation.tags.isEmpty {
            parts.append("tagged \(annotation.tags.joined(separator: ", "))")
        }
        if !annotation.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("has a note")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(motion.animation(Design.Motion.settle)) { expanded.toggle() }
            } label: {
                HStack(spacing: Design.Space.card) {
                    HStack(spacing: Design.Space.tight) {
                        ForEach(session.apps.prefix(4), id: \.applicationName) { app in
                            AppIcon(bundleID: app.bundleIdentifier, appPath: app.appPath, size: Design.Icon.stack)
                        }
                        if session.apps.count > 4 {
                            Text("+\(session.apps.count - 4)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, Design.Pill.countHorizontal).padding(.vertical, Design.Pill.countVertical)
                                .background(Design.Colour.fillStrong, in: Capsule())
                        }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.title).font(Design.Text.itemTitle)
                        Text("\(formatRange(session.startedAt, session.endedAt)) · \(session.apps.count) apps · \(session.switches) switches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    AnnotationMarks(annotation: annotation)
                    Text(formatDurationShort(session.activeSeconds))
                        .font(Design.Text.figure)
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(Design.Space.card)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityDescription)
            .accessibilityHint(expanded ? "Collapses this session" : "Expands this session")
            .accessibilityAddTraits(.isButton)

            if expanded {
                Divider().padding(.horizontal, Design.Space.card)
                VStack(spacing: Design.Space.snug) {
                    ForEach(session.apps, id: \.applicationName) { app in
                        AppShareRow(app: app, maxSeconds: session.apps.first?.seconds ?? 1)
                    }
                }
                .padding(Design.Space.card)

                Divider().padding(.horizontal, Design.Space.card)
                AnnotationEditor(
                    sessionStart: session.startedAt,
                    annotation: annotation,
                    annotations: annotations
                )
                .padding(Design.Space.card)

                // Actions on the whole session, in their own row at the foot of the card —
                // the same shape as the Glaze app, and out of the way until wanted.
                HStack {
                    Spacer()
                    Menu {
                        Button(annotation.bookmarked ? "Remove Bookmark" : "Bookmark") {
                            annotations.setBookmarked(session.startedAt, !annotation.bookmarked)
                        }
                        Menu("Export Session") {
                            ForEach(Report.Format.allCases, id: \.self) { format in
                                Button(format.label) {
                                    // Named for the session, not the day it sits in: one
                                    // session's file should say which session.
                                    export.exportReport(
                                        format, label: session.title, sessions: [session]
                                    )
                                }
                            }
                        }
                        Menu("Share Session") {
                            ForEach(Report.Format.allCases, id: \.self) { format in
                                Button(format.label) {
                                    export.share(
                                        format,
                                        label: session.title,
                                        sessions: [session],
                                        from: NSApp.keyWindow?.contentView
                                    )
                                }
                            }
                        }
                        Divider()
                        Button("Delete Session…", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.horizontal, Design.Space.card)
                .padding(.bottom, Design.Space.row)
            }
        }
        // A bookmarked session gently glows rather than shouting: the same card, warmed.
        .card(border: annotation.bookmarked ? Design.Colour.markedBorder : Design.Colour.border)
        // The same actions on right-click, because that is where a Mac user looks first
        // and a ⋯ that only appears once expanded is a menu you have to find.
        .contextMenu {
            Button(annotation.bookmarked ? "Remove Bookmark" : "Bookmark") {
                annotations.setBookmarked(session.startedAt, !annotation.bookmarked)
            }
            Divider()
            Menu("Export Session") {
                ForEach(Report.Format.allCases, id: \.self) { format in
                    Button(format.label) {
                        export.exportReport(format, label: session.title, sessions: [session])
                    }
                }
            }
            Menu("Share Session") {
                ForEach(Report.Format.allCases, id: \.self) { format in
                    Button(format.label) {
                        export.share(
                            format, label: session.title, sessions: [session],
                            from: NSApp.keyWindow?.contentView
                        )
                    }
                }
            }
            Divider()
            Button("Delete Session…", role: .destructive, action: onDelete)
        }
    }
}

private struct AppShareRow: View {
    let app: SessionApp
    let maxSeconds: Int

    var body: some View {
        HStack(spacing: Design.Space.row) {
            AppIcon(bundleID: app.bundleIdentifier, appPath: app.appPath, size: Design.Icon.inline)
            Text(app.applicationName).font(.subheadline).frame(width: Design.Layout.appNameColumn, alignment: .leading)
            GeometryReader { geometry in
                let fraction = maxSeconds > 0 ? Double(app.seconds) / Double(maxSeconds) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Design.Colour.fill).frame(height: Design.Layout.ringThickness)
                    Capsule().fill(.tint)
                        .frame(
                            width: geometry.size.width * fraction,
                            height: Design.Layout.ringThickness
                        )
                }
                .frame(height: geometry.size.height, alignment: .center)
            }
            .frame(height: Design.Layout.barRow)
            Text(formatDurationShort(app.seconds))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: Design.Layout.durationColumn, alignment: .trailing)
        }
        // The bar is a picture of the number beside it; announcing both would say the
        // same thing twice.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(app.applicationName), \(formatDurationShort(app.seconds))")
    }
}

/// A gap in the day, named for what it was — away, idle, or not recorded.
struct BreakRow: View {
    let gap: ActivityBreak

    private var label: String {
        switch gap.reason {
        case .away: "\(formatDurationShort(gap.seconds)) away"
        case .idle: "\(formatDurationShort(gap.seconds)) idle in \(gap.applicationName ?? "one app")"
        case .unrecorded: "\(formatDurationShort(gap.seconds)) not recorded"
        }
    }

    private var detail: String {
        switch gap.reason {
        case .away: "No keyboard or mouse activity"
        case .idle: "One app held focus without input"
        case .unrecorded: "Replay wasn't running, or tracking was paused"
        }
    }

    var body: some View {
        HStack(spacing: Design.Space.inline) {
            Rectangle().fill(.quaternary).frame(width: Design.Icon.inline, height: Design.Layout.hairline)
            Image(systemName: gap.reason == .unrecorded ? "circle.slash" : "moon.zzz")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            // The figure ("8m away") is the point and the explanation supports it, so the
            // explanation truncates rather than wrapping. Not `layoutPriority(-1)`, which
            // starved it to nothing at every width — a row that silently drops half its
            // meaning is worse than one that wraps.
            Text(detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
            Rectangle().fill(.quaternary).frame(height: 1)
        }
        .padding(.vertical, Design.Space.hairline)
    }
}

/// A real macOS application icon.
///
/// Verified to work under App Sandbox with no entitlement — see docs/FINDINGS.md. Icons are
/// cached because the timeline asks for the same handful over and over.
struct AppIcon: View {
    let bundleID: String?
    let appPath: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let image = IconCache.shared.icon(bundleID: bundleID, appPath: appPath) {
                Image(nsImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: size * 0.22).fill(.quaternary)
            }
        }
        .frame(width: size, height: size)
    }
}

@MainActor
final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]

    func icon(bundleID: String?, appPath: String?) -> NSImage? {
        let key = bundleID ?? appPath ?? ""
        guard !key.isEmpty else { return nil }
        if let hit = cache[key] { return hit }

        var path = appPath
        if path == nil, let bundleID {
            path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
        }
        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[key] = image
        return image
    }
}
