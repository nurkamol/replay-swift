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

    /// The magnification, as a whole percentage. Built as a `String` rather than
    /// interpolated: `Text` would group-separate it, and "1,000%" is not a thing.
    private var zoomLabel: String { "\(Int((scale * 100).rounded()))%" }

    /// Zoom about the middle of the view.
    ///
    /// The offset is scaled by the same ratio, which is what keeps whatever you were looking
    /// at where it was — zoom that quietly slides the field somewhere else costs you your
    /// place, and finding it again is the whole cost of the gesture.
    private func zoom(by factor: CGFloat) {
        let target = min(
            max(zoom * factor, Design.Layout.canvasMinZoom), Design.Layout.canvasMaxZoom
        )
        guard target != zoom else { return }
        let ratio = target / zoom
        withAnimation(motion.animation(Design.Motion.settle)) {
            offset.width *= ratio
            offset.height *= ratio
            zoom = target
        }
    }

    /// Bring one node to the middle and move in on it. What a double-click should do: the
    /// thing you pointed at becomes the thing you are looking at, without losing the field
    /// around it.
    private func focus(on node: CanvasGraph.Node) {
        guard let point = canvas.positions[node.id] else { return }
        let target = Design.Layout.canvasFocusZoom
        withAnimation(motion.animation(Design.Motion.settle)) {
            zoom = target
            offset = CGSize(width: -point.x * target, height: -point.y * target)
            selected = node
        }
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
            ToolbarItemGroup {
                Button { zoom(by: 1 / Design.Layout.canvasZoomStep) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .disabled(scale <= Design.Layout.canvasMinZoom)
                .help("Zoom out")
                .accessibilityLabel("Zoom out")

                // The current magnification, so the buttons are not the only way to know
                // where you are. Announced as a percentage rather than a multiplier.
                Text(zoomLabel)
                    .font(Design.Text.detail)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .frame(width: Design.Layout.canvasZoomReadoutWidth)
                    .accessibilityLabel("Zoom \(zoomLabel)")

                Button { zoom(by: Design.Layout.canvasZoomStep) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .disabled(scale >= Design.Layout.canvasMaxZoom)
                .help("Zoom in")
                .accessibilityLabel("Zoom in")

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
                .help("Fit to the window")
                .accessibilityLabel("Recentre the canvas")
            }
        }
        // The shortcuts every Mac app uses for magnification, so the toolbar is not the only
        // way in. Bound on the view rather than in the menu bar: they mean nothing anywhere
        // else in the app.
        .background {
            Group {
                Button("Zoom In") { zoom(by: Design.Layout.canvasZoomStep) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Zoom In") { zoom(by: Design.Layout.canvasZoomStep) }
                    .keyboardShortcut("=", modifiers: .command)
                Button("Zoom Out") { zoom(by: 1 / Design.Layout.canvasZoomStep) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") {
                    withAnimation(motion.animation(Design.Motion.settle)) {
                        zoom = 1
                        offset = .zero
                    }
                }
                .keyboardShortcut("0", modifiers: .command)
            }
            .opacity(0)
            .accessibilityHidden(true)
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

                    // An application's own icon when there is one and there is room for it:
                    // a field of real icons is recognisable at a glance in a way a field of
                    // coloured dots never is. Clipped to the circle so the field keeps one
                    // shape, and ringed so the node's *kind* survives wearing another
                    // thing's face — a project built on Terminal must not read as Terminal.
                    let icon = radius >= Design.Layout.canvasIconThreshold
                        ? context.resolveSymbol(id: node.id)
                        : nil
                    if let icon {
                        context.drawLayer { layer in
                            layer.clip(to: Circle().path(in: box))
                            layer.draw(icon, in: box)
                        }
                        context.stroke(
                            Circle().path(in: box),
                            with: .color(ring(for: node)),
                            lineWidth: node.type == .app
                                ? Design.Layout.canvasRingWidth
                                : Design.Layout.canvasRingWidthStrong
                        )
                        // A project or a chapter is wearing its lead application's face, so
                        // it says what it *is* in the corner. An application needs no badge:
                        // its own icon is already the whole answer.
                        if let badge = badgeSymbol(for: node),
                           radius >= Design.Layout.canvasBadgeRadius * 2,
                           let glyph = context.resolveSymbol(id: "badge:\(badge)") {
                            let size = Design.Layout.canvasBadgeRadius
                            let corner = CGPoint(
                                x: box.maxX - size * 0.7, y: box.maxY - size * 0.7
                            )
                            let disc = CGRect(
                                x: corner.x - size, y: corner.y - size,
                                width: size * 2, height: size * 2
                            )
                            context.fill(Circle().path(in: disc), with: .color(ring(for: node)))
                            context.draw(glyph, at: corner, anchor: .center)
                        }
                    } else {
                        context.fill(Circle().path(in: box), with: .color(colour(for: node)))
                        // A collection has no application behind it, so it wears the glyph
                        // it wears everywhere else in the app rather than a blank disc.
                        if node.type == .collection,
                           radius >= Design.Layout.canvasIconThreshold,
                           let glyph = context.resolveSymbol(id: "collection:\(node.ref)") {
                            context.draw(glyph, at: at, anchor: .center)
                        }
                    }

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
                }

                // Labels last, and placed greedily: walk the nodes in descending
                // significance and keep a name only when its box clears every box already
                // placed. Two overlapping labels are less readable than one, and dropping
                // the *smaller* node's name is the choice a person would make. The selected
                // node always keeps its own, whatever it collides with.
                var placed: [CGRect] = []
                let ordered = canvas.graph.nodes
                    .filter { $0.id == selected?.id }
                    + canvas.graph.nodes
                        .filter { $0.id != selected?.id }
                        .sorted { self.radius(for: $0) > self.radius(for: $1) }
                for node in ordered {
                    guard let point = canvas.positions[node.id] else { continue }
                    let radius = self.radius(for: node) * scale
                    guard radius > Design.Layout.canvasLabelThreshold else { continue }
                    let at = place(point)
                    let text = context.resolve(
                        Text(node.label).font(Design.Text.micro).foregroundStyle(.secondary)
                    )
                    let size = text.measure(
                        in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
                    )
                    let origin = CGPoint(
                        x: at.x - size.width / 2, y: at.y + radius + Design.Space.inline
                    )
                    let box = CGRect(origin: origin, size: size)
                        .insetBy(
                            dx: -Design.Layout.canvasLabelPadding,
                            dy: -Design.Layout.canvasLabelPadding
                        )
                    let isSelected = node.id == selected?.id
                    if !isSelected && placed.contains(where: { $0.intersects(box) }) { continue }
                    placed.append(box)
                    context.draw(text, at: origin, anchor: .topLeading)
                }
            } symbols: {
                // Declared once at a fixed size and resolved per frame from the cache, so
                // panning does not re-rasterise anything. Only nodes that actually have an
                // application behind them appear here; the rest fall back to a dot.
                ForEach(canvas.graph.nodes.filter(hasIcon), id: \.id) { node in
                    AppIcon(
                        bundleID: node.bundleID,
                        appPath: node.appPath,
                        size: Design.Layout.canvasSymbolSize
                    )
                    .tag(node.id)
                }
                // A collection's own glyph, the same one it wears on the Collections
                // surface, so the two read as the same thing.
                ForEach(Collections.categories.map(\.category), id: \.self) { category in
                    Image(systemName: collectionSymbol(category))
                        .font(Design.Text.prose)
                        .foregroundStyle(.white)
                        .tag("collection:\(category.rawValue)")
                }
                ForEach(["shippingbox.fill", "book.closed.fill", "sparkle"], id: \.self) { name in
                    Image(systemName: name)
                        .font(.system(size: Design.Layout.canvasBadgeGlyph, weight: .semibold))
                        .foregroundStyle(.white)
                        .tag("badge:\(name)")
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
            .onTapGesture(count: 2) { location in
                if let node = node(at: location, centre: centre) { focus(on: node) }
            }
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

    /// Whether this node has an application to show. A collection is a kind of work rather
    /// than a thing you can open, and a moment only has one when it is about an application.
    private func hasIcon(_ node: CanvasGraph.Node) -> Bool {
        node.appPath != nil || node.bundleID != nil
    }

    /// What a node that borrows another thing's icon puts in its corner.
    private func badgeSymbol(for node: CanvasGraph.Node) -> String? {
        switch node.type {
        case .project: "shippingbox.fill"
        case .chapter: "book.closed.fill"
        case .moment: "sparkle"
        case .app, .collection: nil
        }
    }

    /// The ring around an icon, which is what carries the node's kind once its face is
    /// borrowed. Quiet on an application, solid on everything built from one.
    private func ring(for node: CanvasGraph.Node) -> Color {
        switch node.type {
        case .app: .secondary.opacity(Design.Colour.canvasRingQuiet)
        case .project: .accentColor
        case .chapter: .orange
        case .moment: .yellow
        case .collection: .accentColor
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
