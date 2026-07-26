import ReplayCore
import SwiftUI

/// One application's own history, reached from a row in Apps.
///
/// Descriptive throughout. "Avg. visit" is a measurement, not a verdict — a short average is
/// what checking a mail client looks like and a long one is what an editor looks like, and
/// neither is better (SPEC §8).
struct AppHistoryView: View {
    let bundleID: String
    let history: AppHistoryModel
    let annotations: AnnotationsModel
    let export: ExportModel
    let onDeleteSession: (ActivitySession) -> Void

    @Environment(\.motion) private var motion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.block) {
                if history.loaded && history.figures.visits == 0 {
                    empty.centredInPage()
                } else {
                    header
                    tiles
                    if !history.collections.isEmpty { appearsIn }
                    if !history.sessions.isEmpty { recent }
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle(history.name)
        .task(id: bundleID) { history.load(bundleID: bundleID) }
    }

    private var header: some View {
        HStack(spacing: Design.Space.section) {
            AppIcon(bundleID: bundleID, appPath: history.appPath, size: Design.Icon.appHeader)
            VStack(alignment: .leading, spacing: Design.Space.hairline) {
                Text(history.name).font(Design.Text.title).lineLimit(1)
                Text(
                    "\(formatDurationShort(history.figures.lastWeek)) this week · "
                        + "\(history.figures.visits) \(history.figures.visits == 1 ? "visit" : "visits")"
                )
                .font(Design.Text.body)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .settlesIntoView(reduced: motion.reduced)
        .accessibilityElement(children: .combine)
    }

    private var tiles: some View {
        HStack(spacing: Design.Space.row) {
            tile("Today", history.figures.today)
            tile("Yesterday", history.figures.yesterday)
            tile("Last 7 days", history.figures.lastWeek)
            tile("Avg. visit", history.figures.averageVisit)
        }
        .settlesIntoView(reduced: motion.reduced)
    }

    private func tile(_ label: String, _ seconds: Int) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.tight) {
            Text(label).cardLabelStyle()
            Text(formatDurationShort(seconds))
                .font(Design.Text.figure)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Space.card)
        .card(border: Design.Colour.borderQuiet)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(formatDurationShort(seconds))")
    }

    private var appearsIn: some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text("Appears in").sectionLabelStyle()
            // A wrapping row rather than a list: these are labels on the app, not a menu.
            FlowRow(spacing: Design.Space.inline) {
                ForEach(history.collections, id: \.self) { category in
                    Text(Collections.label(for: category))
                        .font(Design.Text.detail.weight(.medium))
                        .padding(.horizontal, Design.Pill.horizontal)
                        .padding(.vertical, Design.Pill.vertical)
                        .background(
                            Capsule().fill(Design.Colour.surface)
                        )
                        .overlay(Capsule().strokeBorder(Design.Colour.border))
                }
            }
        }
        .settlesIntoView(reduced: motion.reduced)
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text("Recent sessions").sectionLabelStyle()
            VStack(spacing: Design.Space.row) {
                ForEach(history.sessions, id: \.startedAt) { session in
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
            Label("No recent history", systemImage: "clock")
        } description: {
            Text("Nothing was recorded for this application in the last thirty days.")
        }
    }
}

/// A row that wraps onto the next line when it runs out of width.
///
/// SwiftUI has no wrapping stack, and a `LazyVGrid` with fixed columns would leave a ragged
/// gap after a short label. This lays each subview at its own width, which is what a row of
/// pills wants.
struct FlowRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
