import ReplayCore
import SwiftUI

/// One project: how it grew, what it is made of, and everything that happened under it.
struct ProjectDetailView: View {
    let id: String
    let projects: ProjectsModel
    let annotations: AnnotationsModel
    let export: ExportModel
    let onDeleteSession: (ActivitySession) -> Void
    let onOpenApp: (String) -> Void
    let onOpenDay: (Int64) -> Void

    @State private var renaming = false
    @State private var draft = ""

    private var named: ProjectsModel.Named? { projects.project(id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.block) {
                if let named {
                    header(named)
                    tiles(named.project)
                    milestones(named.project)
                    apps(named.project)
                    sessions(named.project)
                } else {
                    missing.centredInPage()
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle(named?.name ?? "Project")
        .onAppear { if !projects.loaded { projects.load() } }
        .alert(Loc.t("Rename project"), isPresented: $renaming) {
            TextField(named.map { projectDefaultName($0.project) } ?? "", text: $draft)
            Button(Loc.t("Save")) { projects.rename(id, to: draft) }
            Button(Loc.t("Cancel"), role: .cancel) {}
        } message: {
            Text(Loc.t("Leave it empty to go back to the name Replay chose."))
        }
    }

    private func header(_ named: ProjectsModel.Named) -> some View {
        HStack(spacing: Design.Space.card) {
            VStack(alignment: .leading, spacing: Design.Space.hairline) {
                Text(named.name).font(Design.Text.title).lineLimit(2)
                if named.named {
                    // Only when a name was typed: repeating Replay's own description
                    // underneath Replay's own description would be noise.
                    Text(projectDefaultName(named.project))
                        .font(Design.Text.detail)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: Design.Space.inline)
            Button(Loc.t("Rename…")) {
                draft = named.named ? named.name : ""
                renaming = true
            }
        }
        .settlesIn(0)
    }

    private func tiles(_ project: Project) -> some View {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return HStack(spacing: Design.Space.row) {
            tile("First seen", shortDateLabel(project.firstSeen))
            tile("Last active", relativeDayLabel(project.lastActive, now: now))
            tile(project.sessionCount == 1 ? "Session" : "Sessions", "\(project.sessionCount)")
            tile("Total", formatDurationShort(project.totalSeconds))
        }
        .settlesIn(1)
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.tight) {
            Text(label).cardLabelStyle()
            Text(value).font(Design.Text.figure).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Space.card)
        .card(border: Design.Colour.borderQuiet)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: Loc.t("%@, %2$@"), "\(label), \(value)"))
    }

    /// The sessions that mark a project's beginning, its deepest focus and its most recent
    /// touch — a small timeline of how it grew.
    @ViewBuilder
    private func milestones(_ project: Project) -> some View {
        let byTime = project.sessions.sorted { $0.startedAt < $1.startedAt }
        if let first = byTime.first, let last = byTime.last {
            // `max(by:)` keeps the first of equal elements, which is what the reference's
            // reduce does — a tie must narrate the earlier session, not the later one.
            let longest = project.sessions.max { $0.activeSeconds < $1.activeSeconds } ?? first
            VStack(alignment: .leading, spacing: Design.Space.row) {
                Text(Loc.t("How it grew")).sectionLabelStyle()
                VStack(spacing: 0) {
                    milestone("flag", "First session", first)
                    milestone(
                        "hourglass",
                        "Longest focus · \(formatDurationShort(longest.activeSeconds))",
                        longest
                    )
                    if last.startedAt != first.startedAt {
                        milestone("mappin.and.ellipse", "Most recent", last)
                    }
                }
                .padding(Design.Space.snug)
                .card(border: Design.Colour.borderQuiet)
            }
            .settlesIn(2)
        }
    }

    private func milestone(_ glyph: String, _ label: String, _ session: ActivitySession) -> some View {
        Button {
            onOpenDay(startOfLocalDay(session.startedAt))
        } label: {
            HStack(spacing: Design.Space.card) {
                Image(systemName: glyph)
                    .font(Design.Text.detail)
                    .foregroundStyle(.tint)
                    .frame(width: Design.Icon.glyphColumn)
                VStack(alignment: .leading, spacing: 0) {
                    Text(label).font(Design.Text.detail.weight(.medium))
                    Text(session.title)
                        .font(Design.Text.micro)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: Design.Space.inline)
                Text(shortDateLabel(session.startedAt))
                    .font(Design.Text.micro)
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                Image(systemName: "chevron.right")
                    .font(Design.Text.micro)
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, Design.Space.snug)
            .padding(.vertical, Design.Space.inline)
            .contentShape(Rectangle())
        }
        .buttonStyle(.row)
        .accessibilityHint(Loc.t("Opens the day this happened"))
    }

    private func apps(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text(Loc.t("Frequently used apps")).sectionLabelStyle()
            VStack(spacing: 0) {
                ForEach(project.apps, id: \.applicationName) { app in
                    Button {
                        app.bundleIdentifier.map(onOpenApp)
                    } label: {
                        HStack(spacing: Design.Space.card) {
                            AppIcon(
                                bundleID: app.bundleIdentifier,
                                appPath: app.appPath,
                                size: Design.Icon.stack
                            )
                            Text(app.applicationName).font(Design.Text.detail.weight(.medium))
                            Spacer(minLength: Design.Space.inline)
                            Text(formatDurationShort(app.seconds))
                                .font(Design.Text.detail)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, Design.Space.snug)
                        .padding(.vertical, Design.Space.snug)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.row)
                    .disabled(app.bundleIdentifier == nil)
                }
            }
            .padding(Design.Space.snug)
            .card(border: Design.Colour.borderQuiet)
        }
        .settlesIn(3)
    }

    private func sessions(_ project: Project) -> some View {
        // Twenty, as upstream: a project with two hundred sessions under it is a scroll, not
        // a record, and the day view is where the rest actually lives.
        let shown = Array(project.sessions.prefix(20))
        return VStack(alignment: .leading, spacing: Design.Space.row) {
            Text(project.sessions.count == 1 ? "1 session" : "\(project.sessions.count) sessions")
                .sectionLabelStyle()
            VStack(spacing: Design.Space.row) {
                ForEach(shown, id: \.startedAt) { session in
                    SessionCard(
                        session: session,
                        annotations: annotations,
                        export: export,
                        onDelete: { onDeleteSession(session) }
                    )
                }
            }
            if project.sessions.count > shown.count {
                Text(String(format: Loc.t("Showing the most recent %@."), "\(shown.count)"))
                    .font(Design.Text.detail)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var missing: some View {
        ContentUnavailableView {
            Label(Loc.t("Project not found"), systemImage: "shippingbox")
        } description: {
            Text(
                "A project exists only while its applications keep coming back together. "
                    + "This one has not recurred in the kept history."
            )
        }
    }
}
