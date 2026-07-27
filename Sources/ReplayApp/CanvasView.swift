import AppKit
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
    /// Given so a session in the side panel can lead into the day it happened on.
    let onOpenDay: (Int64) -> Void

    @Environment(\.motion) private var motion
    @State private var offset = CGSize.zero
    @State private var dragged = CGSize.zero
    @State private var zoom: CGFloat = 1
    @State private var pinch: CGFloat = 1
    @State private var selected: CanvasGraph.Node?
    /// What the selected node is joined to, held rather than recomputed: the field redraws
    /// sixty times a second while it moves and this changes only when the selection does.
    @State private var neighbourhood: Set<String> = []
    /// Whether the field is *focused* on the selection — everything unconnected pulled back
    /// so one memory and its surroundings are what is left. On by default, because a
    /// selection that changes nothing about the picture is not a selection.
    @State private var focusMode = true
    /// Whether the timeline beside the field is showing.
    @State private var panelOpen = false
    @State private var dragging = false
    /// When the last click landed, so a second one soon after is a double.
    @State private var lastClick: (id: String, at: Date)?
    /// When the entrance began, and whether it has finished.
    ///
    /// A `Canvas` does not interpolate — SwiftUI animates view properties, and everything
    /// inside a canvas is drawn in one pass from whatever the values are at that instant. So
    /// the entrance is driven by a clock: a `TimelineView` while it runs, and a plain canvas
    /// the moment it is done, because a timeline still ticking afterwards is a redraw every
    /// frame for nothing.
    @State private var entranceStart = Date()
    @State private var entranceDone = false
    @State private var scrollMonitor: Any?

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

    private func watchScrollWheel() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // A trackpad sends precise deltas that are already small; a wheel sends coarse
            // lines, scaled here to land in the same range.
            let delta = event.hasPreciseScrollingDeltas
                ? event.scrollingDeltaY
                : event.scrollingDeltaY * Design.Layout.canvasWheelLineScale
            if delta != 0 {
                zoom(by: 1 + delta * Design.Layout.canvasWheelSensitivity)
            }
            // Swallowed: this surface has nothing else that scrolls, and letting it through
            // would scroll whatever is behind while the field zooms.
            return nil
        }
    }

    /// A click: select, or focus when it is the second on the same node.
    ///
    /// Double-click is timed rather than declared, because declaring one made SwiftUI hold
    /// every single click back to see whether a second was coming — exactly the hesitation
    /// this surface should not have.
    private func click(at location: CGPoint, centre: CGPoint) {
        let hit = node(at: location, centre: centre)
        let now = Date()
        if let hit, let last = lastClick, last.id == hit.id,
           now.timeIntervalSince(last.at) < Design.Motion.doubleClickSeconds {
            lastClick = nil
            focus(on: hit)
            return
        }
        lastClick = hit.map { ($0.id, now) }
        withAnimation(motion.animation(Design.Motion.settle)) { select(hit) }
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
            select(node)
        }
    }

    private func select(_ node: CanvasGraph.Node?) {
        selected = node
        neighbourhood = node.map { canvas.graph.neighbours(of: $0.id) } ?? []
    }

    /// How strongly a node reads right now.
    ///
    /// Focus is a *dimming*, not a hiding: the rest of the field stays visible so the thing
    /// you focused is still somewhere, rather than alone on an empty page. Everything at
    /// full weight when nothing is selected, which is the ordinary state.
    private func emphasis(_ id: String) -> Double {
        guard focusMode, selected != nil else { return 1 }
        return neighbourhood.contains(id) ? 1 : Design.Colour.canvasUnfocused
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if canvas.loaded && canvas.graph.nodes.isEmpty {
                    empty.centredInPage()
                } else {
                    field
                    if let selected { preview(selected) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if panelOpen {
                Divider()
                timelinePanel
                    .transition(motion.transition(.move(edge: .trailing)))
            }
        }
        .animation(motion.animation(Design.Motion.settle), value: panelOpen)
        .background(.background)
        .navigationTitle("Canvas")
        .navigationSubtitle("Your history as a landscape")
        // The wheel, which SwiftUI has no modifier for. Pinch is the trackpad gesture and
        // already works; this is the mouse, and two fingers on a trackpad, which would
        // otherwise do nothing at all on an obviously zoomable surface.
        //
        // A local monitor rather than an `NSView`: a view behind the canvas never sees the
        // event, because `scrollWheel` walks *up* the responder chain rather than across to
        // a sibling, and one in front would swallow the clicks. Installed only while this
        // surface is on screen, and removed with it.
        .onAppear { watchScrollWheel() }
        .onDisappear {
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
            scrollMonitor = nil
        }
        .onAppear {
            if !canvas.loaded { canvas.load() }
            // Restarted on every appearance, so coming back plays it again rather than
            // showing a field that is simply already there.
            entranceDone = false
            entranceStart = Date()
        }
        .task(id: entranceStart) {
            try? await Task.sleep(for: .seconds(Design.Motion.canvasEntranceSeconds))
            entranceDone = true
        }
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $focusMode) {
                    Image(systemName: focusMode
                        ? "circle.dashed.inset.filled" : "circle.dashed")
                }
                .toggleStyle(.button)
                .help(focusMode
                    ? "Stop pulling back everything unconnected"
                    : "Pull back everything not connected to the selection")
                .accessibilityLabel("Focus on the selection")

                Toggle(isOn: $panelOpen) {
                    Image(systemName: "sidebar.right")
                }
                .toggleStyle(.button)
                .help("Show the sessions behind the selection")
                .accessibilityLabel("Timeline panel")

                Divider()

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
                        select(nil)
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
            animatedField(centre: centre)
            .contentShape(Rectangle())
            // One gesture, not three. Two `onTapGesture`s and a drag were being arbitrated
            // by SwiftUI and the single click lost outright — clicking a node did nothing at
            // all. A zero-distance drag reports both press and release, so a click is simply
            // a drag that never went anywhere and there is nothing left to arbitrate.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if hypot(value.translation.width, value.translation.height)
                            > Design.Layout.canvasClickSlop {
                            dragging = true
                            dragged = value.translation
                        }
                    }
                    .onEnded { value in
                        if dragging {
                            offset.width += value.translation.width
                            offset.height += value.translation.height
                        } else {
                            click(at: value.location, centre: centre)
                        }
                        dragging = false
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

    /// The field, on a clock while it is arriving and off it once it has.
    @ViewBuilder
    private func animatedField(centre: CGPoint) -> some View {
        if entranceDone || motion.reduced {
            renderField(centre: centre, progress: 1)
        } else {
            // Qualified: this app has its own `TimelineView` — the Timeline surface — and
            // it shadows SwiftUI's inside this module.
            SwiftUI.TimelineView(.animation) { timeline in
                renderField(centre: centre, progress: progress(at: timeline.date))
            }
        }
    }

    /// How far through its entrance the field is, 0 to 1, at a given instant.
    private func progress(at date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSince(entranceStart)
        return CGFloat(min(1, max(0, elapsed / Design.Motion.canvasEntranceSeconds)))
    }

    /// How far into its own entrance one node is.
    ///
    /// Staggered by weight rather than by index, so the busiest arrive first and the field
    /// grows outward from what matters — which is the order the eye would find them in
    /// anyway. Eased, so each one settles rather than snapping to full size.
    private func entrance(_ node: CanvasGraph.Node, _ progress: CGFloat) -> CGFloat {
        guard progress < 1 else { return 1 }
        let rank = order[node.id] ?? 0
        let start = min(
            CGFloat(rank) * Design.Motion.canvasEntranceStagger,
            Design.Motion.canvasEntranceStaggerCap
        )
        let local = (progress - start) / max(0.0001, 1 - start)
        let clamped = min(1, max(0, local))
        // Ease out: fast to most of its size, then settling.
        return 1 - pow(1 - clamped, 3)
    }

    /// Each node's place in the entrance, busiest first. Computed once per graph rather than
    /// per frame — this runs sixty times a second while the field assembles.
    private var order: [String: Int] {
        let ranked = canvas.graph.nodes.sorted { radius(for: $0) > radius(for: $1) }
        var result: [String: Int] = [:]
        for (rank, node) in ranked.enumerated() { result[node.id] = rank }
        return result
    }

    /// Everything drawn, in one pass.
    private func renderField(centre: CGPoint, progress: CGFloat) -> some View {
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
                    // An edge is only lit when it touches the focus. A line between two
                    // dimmed nodes that stayed bright would draw the eye to the part of the
                    // field focus is meant to push back.
                    let lit = min(emphasis(edge.a), emphasis(edge.b))
                    let weight: Double = (Design.Colour.canvasEdgeFloor
                        + strength * Design.Colour.canvasEdgeRange) * Double(progress) * lit
                    context.stroke(
                        path,
                        with: .color(.secondary.opacity(weight)),
                        lineWidth: Design.Layout.canvasEdgeWidth
                    )
                }

                for node in canvas.graph.nodes {
                    guard let point = canvas.positions[node.id] else { continue }
                    let grown = entrance(node, progress)
                    if grown <= 0.001 { continue }
                    let at = place(point)
                    let radius = self.radius(for: node) * scale * grown
                    context.opacity = emphasis(node.id)
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
                    context.opacity = 1
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
                    context.opacity = emphasis(node.id)
                    context.draw(text, at: origin, anchor: .topLeading)
                    context.opacity = 1
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
    }

    /// The timeline beside the field: the sessions behind whatever is selected.
    ///
    /// The other half of the same view rather than a second surface — selecting a memory on
    /// the canvas fills this in, and a session here opens the day it happened on. Kept to
    /// ``CanvasGraph/focusSessionLimit``, because this is the timeline behind *one* memory.
    private var timelinePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Design.Space.hairline) {
                Text("Timeline").cardLabelStyle()
                Text(selected?.label ?? "Nothing selected")
                    .font(Design.Text.itemTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Design.Space.section)

            Divider()

            if selected == nil {
                panelNote("Select a memory on the canvas to see the sessions behind it here.")
            } else if panelSessions.isEmpty {
                panelNote("No sessions in the kept window for this memory.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(panelSessions, id: \.startedAt) { session in
                            panelRow(session)
                        }
                    }
                    .padding(Design.Space.inline)
                }
            }
        }
        .frame(width: Design.Layout.canvasPanelWidth)
        .background(Design.Colour.surfaceQuiet)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sessions behind the selection")
    }

    private var panelSessions: [ActivitySession] {
        guard let selected else { return [] }
        return canvas.graph.sessions(
            behind: selected,
            in: canvas.sessions,
            projectSessions: canvas.projectSessions,
            chapterDays: canvas.chapterDays
        )
    }

    private func panelNote(_ text: String) -> some View {
        Text(text)
            .font(Design.Text.detail)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Design.Space.page)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func panelRow(_ session: ActivitySession) -> some View {
        Button {
            onOpenDay(startOfLocalDay(session.startedAt))
        } label: {
            HStack(spacing: Design.Space.inline) {
                VStack(alignment: .leading, spacing: Design.Space.hairline) {
                    Text(session.title)
                        .font(Design.Text.detail.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(
                        "\(formatRange(session.startedAt, session.endedAt)) · "
                            + formatDurationShort(session.activeSeconds)
                    )
                    .font(Design.Text.micro)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .lineLimit(1)
                }
                Spacer(minLength: Design.Space.tight)
                Image(systemName: "chevron.right")
                    .font(Design.Text.micro)
                    .foregroundStyle(.quaternary)
            }
            .padding(Design.Space.inline)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the day this happened on")
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
