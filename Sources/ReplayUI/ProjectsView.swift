import ReplayCore
import SwiftUI

/// The recurring combinations of apps behind your work — remembered, and yours to name.
///
/// Nothing here was filed. A project appears because the same apps kept coming back, and
/// stops appearing when that stops being true. Replay names one descriptively to begin with
/// because a description is a fact; what the work actually *is* is something only you know,
/// which is why you can type it.
struct ProjectsView: View {
    let projects: ProjectsModel
    let onOpen: (String) -> Void


    /// Two across when there is room, one when there is not — a project card carries a name,
    /// two figures and a row of icons, and needs about half a window to do it.
    private let columns = [GridItem(.adaptive(minimum: Design.Layout.cardMinWidth), spacing: Design.Space.row)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.block) {
                if projects.projects.isEmpty {
                    empty.centredInPage()
                } else {
                    LazyVGrid(columns: columns, spacing: Design.Space.row) {
                        // Each card on its own beat. The stagger used to sit on the grid, so
                        // twelve projects arrived as one block where upstream deals them out.
                        ForEach(Array(projects.projects.enumerated()), id: \.element.id) {
                            index, project in
                            ProjectCard(named: project, onOpen: { onOpen(project.id) })
                                .settlesIn(index)
                        }
                    }
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle(Loc.t("Projects"))
        .navigationSubtitle("The apps that keep coming back together")
        .onAppear { projects.load() }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(Loc.t("No projects yet"), systemImage: "shippingbox")
        } description: {
            Text(
                "When the same handful of applications keeps coming back together, "
                    + "Replay gathers those sessions into a project you can name and revisit."
            )
        }
    }
}

private struct ProjectCard: View {
    let named: ProjectsModel.Named
    let onOpen: () -> Void

    private var project: Project { named.project }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Design.Space.card) {
                HStack(alignment: .top, spacing: Design.Space.card) {
                    VStack(alignment: .leading, spacing: Design.Space.hairline) {
                        Text(named.name)
                            .font(Design.Text.itemTitle)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(
                            Loc.count(project.sessionCount, "%@ session", "%@ sessions")
                                + " · "
                                + formatDurationShort(project.totalSeconds)
                        )
                        .font(Design.Text.detail)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    }
                    Spacer(minLength: Design.Space.inline)
                    HStack(spacing: Design.Space.snug) {
                        Text(RuntimeCopy.relativeDayLabel(
                            project.lastActive,
                            now: Int64(Date().timeIntervalSince1970 * 1000)
                        ))
                        .font(Design.Text.micro)
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        Image(systemName: "chevron.right")
                            .font(Design.Text.micro)
                            .foregroundStyle(.quaternary)
                    }
                }
                HStack(spacing: Design.Space.snug) {
                    ForEach(project.apps, id: \.applicationName) { app in
                        AppIcon(
                            bundleID: app.bundleIdentifier,
                            appPath: app.appPath,
                            size: Design.Icon.listItem
                        )
                    }
                    Text(project.apps.map(\.applicationName).joined(separator: ", "))
                        .font(Design.Text.micro)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, Design.Space.tight)
                }
            }
            .padding(Design.Space.section)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.row)
        .focusable()
        .card(border: Design.Colour.border)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(named.name), \(project.sessionCount) sessions, "
                + "\(formatDurationShort(project.totalSeconds)), "
                + project.apps.map(\.applicationName).joined(separator: ", ")
        )
        .accessibilityHint(Loc.t("Opens this project"))
    }
}

#if DEBUG
#Preview("Projects") {
    let world = PreviewWorld().load()
    return ProjectsView(projects: world.projects, onOpen: { _ in })
        .frame(width: Design.Layout.windowWidth, height: Design.Layout.windowHeight)
}
#endif
