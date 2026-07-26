import ReplayCore
import SwiftUI

/// Canvas — your history as a landscape you can move through.
///
/// Applications, the projects and chapters built on them, the kinds of work they gather
/// into, and the moments worth remembering, all tied by relationships that already exist in
/// the data. Nothing here is a guess: an edge means two things genuinely co-occurred.
///
/// Drawn with `Canvas` rather than a stack of views because a hundred nodes and their lines
/// are one drawing, not a hundred layout participants — and because it keeps the field
/// smooth while it is being panned.
struct CanvasView: View {
    let canvas: CanvasModel
    let onOpen: (CanvasGraph.Node) -> Void

    @Environment(\.motion) private var motion
    @State private var offset = CGSize.zero
    @State private var dragged = CGSize.zero
    @State private var zoom: CGFloat = 1
    @State private var pinch: CGFloat = 1
    @State private var selected: CanvasGraph.Node?

    private var scale: CGFloat {
        min(max(zoom * pinch, Design.Layout.canvasMinZoom), Design.Layout.canvasMaxZoom)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if canvas.loaded && canvas.graph.nodes.isEmpty {
                empty.centredInPage()
            } else {
                field
                if let selected { preview(selected) }
            }
        }
        .background(.background)
        .navigationTitle("Canvas")
        .navigationSubtitle("Your history as a landscape")
        .onAppear { if !canvas.loaded { canvas.load() } }
        .toolbar {
            ToolbarItem {
                Button {
                    withAnimation(motion.animation(Design.Motion.settle)) {
                        offset = .zero
                        dragged = .zero
                        zoom = 1
                        selected = nil
                    }
                } label: {
                    Image(systemName: "scope")
                }
                .help("Recentre")
                .accessibilityLabel("Recentre the canvas")
            }
        }
    }

    private var field: some View {
        GeometryReader { geometry in
            let centre = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            Canvas { context, _ in
                func place(_ point: CGPoint) -> CGPoint {
                    CGPoint(
                        x: centre.x + (point.x * scale) + offset.width + dragged.width,
                        y: centre.y + (point.y * scale) + offset.height + dragged.height
                    )
                }

                // Edges first, so nodes sit on top of their own lines.
                for edge in canvas.graph.edges {
                    guard let from = canvas.positions[edge.a],
                          let to = canvas.positions[edge.b] else { continue }
                    var path = Path()
                    path.move(to: place(from))
                    path.addLine(to: place(to))
                    let strength = edge.kind == .appApp && canvas.graph.maxAppWeight > 0
                        ? Double(edge.weight) / Double(canvas.graph.maxAppWeight)
                        : Design.Colour.canvasEdgeBase
                    context.stroke(
                        path,
                        with: .color(.secondary.opacity(
                            Design.Colour.canvasEdgeFloor
                                + strength * Design.Colour.canvasEdgeRange
                        )),
                        lineWidth: Design.Layout.canvasEdgeWidth
                    )
                }

                for node in canvas.graph.nodes {
                    guard let point = canvas.positions[node.id] else { continue }
                    let at = place(point)
                    let radius = self.radius(for: node) * scale
                    let box = CGRect(
                        x: at.x - radius, y: at.y - radius, width: radius * 2, height: radius * 2
                    )
                    context.fill(Circle().path(in: box), with: .color(colour(for: node)))
                    if node.id == selected?.id {
                        context.stroke(
                            Circle().path(in: box.insetBy(
                                dx: -Design.Layout.canvasSelectionInset,
                                dy: -Design.Layout.canvasSelectionInset
                            )),
                            with: .color(.primary),
                            lineWidth: Design.Layout.canvasSelectionWidth
                        )
                    }
                    // Labels only past a certain size: a field of overlapping text at low
                    // zoom is less legible than no text at all.
                    if radius > Design.Layout.canvasLabelThreshold {
                        context.draw(
                            Text(node.label).font(Design.Text.micro).foregroundStyle(.secondary),
                            at: CGPoint(x: at.x, y: at.y + radius + Design.Space.inline),
                            anchor: .top
                        )
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { dragged = $0.translation }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                        dragged = .zero
                    }
            )
            .gesture(
                MagnifyGesture()
                    .onChanged { pinch = $0.magnification }
                    .onEnded { value in
                        zoom = min(
                            max(zoom * value.magnification, Design.Layout.canvasMinZoom),
                            Design.Layout.canvasMaxZoom
                        )
                        pinch = 1
                    }
            )
            .onTapGesture { location in
                withAnimation(motion.animation(Design.Motion.settle)) {
                    selected = node(at: location, centre: centre)
                }
            }
            .accessibilityHidden(true)
        }
        // The picture is not reachable by keyboard, so the same information is offered as a
        // list to anything that reads the screen.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "A map of \(canvas.graph.nodes.count) items from your history and "
                + "\(canvas.graph.edges.count) connections between them. "
                + "The same information is on Apps, Projects and Story."
        )
    }

    /// The preview for whatever is selected, and the way into it.
    private func preview(_ node: CanvasGraph.Node) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.snug) {
            Text(node.type.rawValue.capitalized).cardLabelStyle()
            Text(node.label).font(Design.Text.itemTitle).lineLimit(2)
            Text(node.subtitle)
                .font(Design.Text.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if node.ref.isEmpty {
                Text("Nothing to open for this one.")
                    .font(Design.Text.micro)
                    .foregroundStyle(.tertiary)
            } else {
                Button("Open") { onOpen(node) }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, Design.Space.tight)
            }
        }
        .frame(maxWidth: Design.Layout.canvasPreviewWidth, alignment: .leading)
        .padding(Design.Space.section)
        .background(Design.Material.panel, in: RoundedRectangle(
            cornerRadius: Design.Radius.surface, style: .continuous
        ))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.surface, style: .continuous)
                .strokeBorder(Design.Colour.border)
        )
        .padding(Design.Space.page)
        .transition(motion.transition(.opacity.combined(with: .scale(scale: 0.98))))
        .accessibilityElement(children: .contain)
    }

    /// Weight drives size, so the busiest things read as the biggest. Square-rooted, because
    /// area is what the eye compares and a linear radius would make one long day dwarf a week.
    private func radius(for node: CanvasGraph.Node) -> CGFloat {
        switch node.type {
        case .moment:
            return Design.Layout.canvasMomentRadius
        case .collection:
            return Design.Layout.canvasCollectionRadius
        default:
            let scaled: CGFloat = CGFloat(Double(node.weight).squareRoot())
                * Design.Layout.canvasRadiusScale
            return min(Design.Layout.canvasMaxRadius, Design.Layout.canvasMinRadius + scaled)
        }
    }

    private func colour(for node: CanvasGraph.Node) -> Color {
        switch node.type {
        case .collection: .accentColor
        case .project: .accentColor.opacity(Design.Colour.canvasProjectOpacity)
        case .chapter: .orange.opacity(Design.Colour.canvasChapterOpacity)
        case .moment: .yellow.opacity(Design.Colour.canvasMomentOpacity)
        case .app: .secondary.opacity(Design.Colour.canvasAppOpacity)
        }
    }

    /// The node under a click, nearest first — with a little slack, so a small star does not
    /// demand a pixel-perfect hit.
    private func node(at location: CGPoint, centre: CGPoint) -> CanvasGraph.Node? {
        var best: (node: CanvasGraph.Node, distance: CGFloat)?
        for node in canvas.graph.nodes {
            guard let point = canvas.positions[node.id] else { continue }
            let at = CGPoint(
                x: centre.x + point.x * scale + offset.width + dragged.width,
                y: centre.y + point.y * scale + offset.height + dragged.height
            )
            let distance = hypot(at.x - location.x, at.y - location.y)
            let reach = radius(for: node) * scale + Design.Layout.canvasHitSlack
            if distance <= reach, best == nil || distance < best!.distance {
                best = (node, distance)
            }
        }
        return best?.node
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("Nothing to map yet", systemImage: "sparkles")
        } description: {
            Text(
                "Once there are a few applications, projects and chapters, they will appear "
                    + "here as a landscape you can move through."
            )
        }
    }
}
