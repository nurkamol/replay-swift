import ReplayCore
import SwiftUI

/// Today: the day's headline, then the day itself.
///
/// It describes rather than grades — no targets, no red, no scolding a quiet day. The
/// figures are large because they are the point; everything else is quiet around them.
struct TodayView: View {
    let model: AppModel
    let annotations: AnnotationsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let summary = model.summary, summary.switches > 0 {
                    HeadlineCard(summary: summary)
                    sessionList
                } else {
                    quietDay
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Today")
                .font(.system(size: 28, weight: .bold))
            Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var quietDay: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("A quiet day")
                .font(.headline)
            Text("Nothing recorded yet — your sessions will appear here as you work.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 40)
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(model.sessions.count) \(model.sessions.count == 1 ? "session" : "sessions")")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.6)

            ForEach(Array(model.timeline.enumerated()), id: \.offset) { _, item in
                switch item {
                case .session(let session):
                    SessionCard(
                        session: session,
                        annotations: annotations,
                        onDelete: { model.deleteSession(session) }
                    )
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(formatDurationShort(summary.activeSeconds))
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("active")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 22) {
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
                HStack(spacing: 10) {
                    AppIcon(bundleID: top.bundleIdentifier, appPath: top.appPath, size: 26)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("TOP APP")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .kerning(0.6)
                        Text(top.applicationName).font(.callout.weight(.medium))
                    }
                    Spacer()
                    Text(formatDurationShort(top.seconds))
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                }
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
    }

    private struct Stat: View {
        let value: String
        let label: String
        var body: some View {
            HStack(spacing: 5) {
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
    let onDelete: () -> Void
    @State private var expanded = false

    private var annotation: SessionAnnotation { annotations.annotation(for: session.startedAt) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        ForEach(session.apps.prefix(4), id: \.applicationName) { app in
                            AppIcon(bundleID: app.bundleIdentifier, appPath: app.appPath, size: 22)
                        }
                        if session.apps.count > 4 {
                            Text("+\(session.apps.count - 4)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5).padding(.vertical, 3)
                                .background(.quaternary.opacity(0.5), in: Capsule())
                        }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.title).font(.body.weight(.medium))
                        Text("\(formatRange(session.startedAt, session.endedAt)) · \(session.apps.count) apps · \(session.switches) switches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    AnnotationMarks(annotation: annotation)
                    Text(formatDurationShort(session.activeSeconds))
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().padding(.horizontal, 12)
                VStack(spacing: 6) {
                    ForEach(session.apps, id: \.applicationName) { app in
                        AppShareRow(app: app, maxSeconds: session.apps.first?.seconds ?? 1)
                    }
                }
                .padding(12)

                Divider().padding(.horizontal, 12)
                AnnotationEditor(
                    sessionStart: session.startedAt,
                    annotation: annotation,
                    annotations: annotations
                )
                .padding(12)

                // Actions on the whole session, in their own row at the foot of the card —
                // the same shape as the Glaze app, and out of the way until wanted.
                HStack {
                    Spacer()
                    Menu {
                        Button(annotation.bookmarked ? "Remove Bookmark" : "Bookmark") {
                            annotations.setBookmarked(session.startedAt, !annotation.bookmarked)
                        }
                        Divider()
                        Button("Delete Session…", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
        // A bookmarked session gently glows rather than shouting: the same border, warmed.
        .overlay(
            RoundedRectangle(cornerRadius: 10).strokeBorder(
                annotation.bookmarked ? AnyShapeStyle(.yellow.opacity(0.45))
                    : AnyShapeStyle(.quaternary.opacity(0.5)),
                lineWidth: 1
            )
        )
    }
}

private struct AppShareRow: View {
    let app: SessionApp
    let maxSeconds: Int

    var body: some View {
        HStack(spacing: 10) {
            AppIcon(bundleID: app.bundleIdentifier, appPath: app.appPath, size: 18)
            Text(app.applicationName).font(.subheadline).frame(width: 150, alignment: .leading)
            GeometryReader { geometry in
                let fraction = maxSeconds > 0 ? Double(app.seconds) / Double(maxSeconds) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary.opacity(0.4)).frame(height: 4)
                    Capsule().fill(.tint).frame(width: geometry.size.width * fraction, height: 4)
                }
                .frame(height: geometry.size.height, alignment: .center)
            }
            .frame(height: 12)
            Text(formatDurationShort(app.seconds))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
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
        HStack(spacing: 8) {
            Rectangle().fill(.quaternary).frame(width: 18, height: 1)
            Image(systemName: gap.reason == .unrecorded ? "circle.slash" : "moon.zzz")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(detail).font(.caption).foregroundStyle(.tertiary)
            Rectangle().fill(.quaternary).frame(height: 1)
        }
        .padding(.vertical, 2)
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
