import ReplayCore
import SwiftUI

/// How two applications are used together.
///
/// Reached from an application's "works alongside" list. Everything here is a count of
/// things that happened — switches, shared sessions, which direction — and none of it is a
/// judgement about whether switching that often is good (SPEC §8).
struct RelationshipView: View {
    let keyA: String
    let keyB: String
    let relationships: RelationshipsModel
    let annotations: AnnotationsModel
    let export: ExportModel
    let onDeleteSession: (ActivitySession) -> Void


    private var pair: Relationship? { relationships.pair }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.block) {
                if let pair {
                    header(pair)
                    tiles(pair)
                    direction(pair)
                    sessions(pair)
                } else if relationships.loaded {
                    empty.centredInPage()
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle(pair.map { "\($0.a.applicationName) & \($0.b.applicationName)" } ?? "Together")
        .task(id: "\(keyA)|\(keyB)") { relationships.load(keyA: keyA, keyB: keyB) }
    }

    private func header(_ pair: Relationship) -> some View {
        HStack(spacing: Design.Space.card) {
            AppIcon(
                bundleID: pair.a.bundleIdentifier, appPath: pair.a.appPath,
                size: Design.Icon.resume
            )
            Image(systemName: "arrow.left.arrow.right")
                .font(Design.Text.detail)
                .foregroundStyle(.tertiary)
            AppIcon(
                bundleID: pair.b.bundleIdentifier, appPath: pair.b.appPath,
                size: Design.Icon.resume
            )
            VStack(alignment: .leading, spacing: Design.Space.hairline) {
                Text(String(
                    format: Loc.t("%1$@ & %2$@"),
                    pair.a.applicationName, pair.b.applicationName
                ))
                    .font(Design.Text.title)
                    .lineLimit(2)
                Text(
                    "\(pair.sharedSessions) shared "
                        + "\(pair.sharedSessions == 1 ? "session" : "sessions") · "
                        + Loc.count(pair.switches, "%@ switch", "%@ switches")
                )
                .font(Design.Text.body)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .settlesIn(0)
        .accessibilityElement(children: .combine)
    }

    private func tiles(_ pair: Relationship) -> some View {
        HStack(spacing: Design.Space.row) {
            tile("Switches", String(pair.switches))
            tile("Shared sessions", String(pair.sharedSessions))
            tile("Average together", formatDurationShort(pair.averageTogetherSeconds))
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

    /// Which way the switching tends to run.
    ///
    /// A split bar rather than two numbers: the shape is the point, and "mostly one way" is
    /// something you see faster than you read.
    private func direction(_ pair: Relationship) -> some View {
        let total = max(pair.switches, 1)
        return VStack(alignment: .leading, spacing: Design.Space.row) {
            Text(Loc.t("Which way it goes")).sectionLabelStyle()
            VStack(alignment: .leading, spacing: Design.Space.inline) {
                GeometryReader { geometry in
                    HStack(spacing: Design.Layout.hairline) {
                        Capsule().fill(.tint)
                            .frame(width: geometry.size.width * Double(pair.aToB) / Double(total))
                        Capsule().fill(Design.Colour.fillStrong)
                    }
                    .frame(height: Design.Layout.barThickness)
                    .frame(height: geometry.size.height, alignment: .center)
                }
                .frame(height: Design.Layout.barRow)
                HStack {
                    // Built as a `String` rather than interpolated into `Text` directly:
                    // `Text`'s own interpolation group-separates an `Int`, and a few
                    // thousand switches would read as "1,240".
                    Text(pair.a.applicationName + " → " + pair.b.applicationName
                        + ": " + String(pair.aToB))
                    Spacer(minLength: Design.Space.inline)
                    Text(pair.b.applicationName + " → " + pair.a.applicationName
                        + ": " + String(pair.bToA))
                }
                .font(Design.Text.micro)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            }
            .padding(Design.Space.card)
            .card(border: Design.Colour.borderQuiet)
        }
        .settlesIn(2)
    }

    private func sessions(_ pair: Relationship) -> some View {
        let shown = Array(pair.sessions.prefix(20))
        return VStack(alignment: .leading, spacing: Design.Space.row) {
            Text(Loc.t("Sessions they shared")).sectionLabelStyle()
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
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(NarrativeCopy.relationshipEmptyTitle, systemImage: "arrow.left.arrow.right")
        } description: {
            Text(NarrativeCopy.relationshipEmptyDetail)
        }
    }
}
