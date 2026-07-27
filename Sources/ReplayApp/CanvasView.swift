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
    /// Whether the command palette is open over the top of all this. Passed in rather than
    /// worked out here: the palette covers the field exactly, so no amount of looking at the
    /// pointer can tell the two apart, and a scroll meant for a list of results must not be
    /// taken by the field underneath it.
    let paletteOpen: Bool

    @Environment(\.motion) private var motion
    @Environment(\.themeTint) private var tint
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
    /// Whether the pointer is over the field itself, which is what decides whether a scroll
    /// is this surface's to take.
    @State private var pointerInField = false
    /// ``paletteOpen``, mirrored into state.
    ///
    /// Not redundant, and the reason is a trap worth naming: the scroll monitor's closure is
    /// made once, in `onAppear`, and captures the view *struct* — a value. A plain `let` read
    /// through that capture is whatever it was at capture time, for ever. `@State` is not,
    /// because the property wrapper reads shared storage rather than the copy. So `let
    /// paletteOpen` inside the monitor was permanently `false` and the guard did nothing,
    /// which looked exactly like the guard being wrong rather than being stale.
    @State private var paletteIsOpen = false
    /// Which stop a Replay Story is resting on, and the task flying it. Held so that any
    /// touch of the field can cancel it: a tour that keeps going while you are trying to
    /// drag is the camera fighting you for the wheel.
    @State private var tourStop: String?
    /// The stop the camera has just left, and when it left — between them they are the line
    /// being drawn and the breath being let out, both of which are functions of elapsed time
    /// rather than of state. A `Canvas` does not interpolate: it draws one pass from
    /// whatever the values are at that instant, so anything that moves inside it has to be
    /// read off a clock. Same reason the entrance is driven this way.
    @State private var tourFrom: String?
    @State private var tourArrivedAt = Date()
    @State private var tour: Task<Void, Never>?
    /// When the selection last changed, so its halo can arrive rather than appear.
    @State private var selectedAt = Date()
    /// A flick's leftover speed, in points per second, decaying to rest.
    @State private var glide: Task<Void, Never>?
    /// Where the pointer is in the field, so zoom can keep whatever is under it under it,
    /// and where the middle of the field is — the scroll monitor is outside the geometry
    /// that knows, so it has to be told.
    @State private var pointerAt: CGPoint?
    @State private var fieldCentre: CGPoint = .zero
    /// The node under the pointer.
    ///
    /// The reference has this and the port did not: a field of a hundred things where none
    /// of them reacts to being pointed at gives you no way to tell what is a target and what
    /// is scenery, and no way to read a crowded node's name without clicking it. Upstream a
    /// hovered node is *active* — the same state as the focused one and the tour's current
    /// stop — so it wears a stronger ring, a brighter bubble, and keeps its label even where
    /// collision would have dropped it.
    @State private var hovered: String?

    /// How far the pointer sits from the middle of the field. Zero when it is not over the
    /// field at all, which makes an anchored zoom fall back to a centred one.
    private var pointerAway: CGPoint {
        guard let pointerAt else { return .zero }
        return CGPoint(x: pointerAt.x - fieldCentre.x, y: pointerAt.y - fieldCentre.y)
    }
    /// The camera flight in progress, if there is one.
    ///
    /// Recorded because SwiftUI animates the *rendered* value and will not tell you what it
    /// is: `offset` and `zoom` hold the destination from the instant a flight begins. So
    /// grabbing the field while the camera was moving added the drag to where the camera was
    /// *going* rather than to where it was, and the field jumped when you let go — the exact
    /// failure Apple's fluid-interface talk puts first, "always animate from the presentation
    /// value". Knowing the curve, the start and the duration is enough to evaluate where the
    /// screen actually is and take the camera back at that point.
    @State private var flight: Flight?

    private struct Flight {
        var fromOffset: CGSize
        var toOffset: CGSize
        var fromZoom: CGFloat
        var toZoom: CGFloat
        var started: Date
        var seconds: TimeInterval
    }

    private var scale: CGFloat {
        min(max(zoom * pinch, Design.Layout.canvasMinZoom), Design.Layout.canvasMaxZoom)
    }

    /// The offset the field is actually drawn with.
    ///
    /// While a pinch is under way this keeps whatever is under the pointer under the pointer,
    /// which is what "touch and content move together" means for a zoom: scaling `scale`
    /// alone pins the field's own origin, so the thing being pinched slides out from under
    /// the fingers. The correction is the same arithmetic as an anchored zoom, applied live
    /// rather than at the end, because the ratio is known at every moment of the gesture.
    private func liveOffset(centre: CGPoint) -> CGSize {
        let dragging = CGSize(
            width: offset.width + dragged.width, height: offset.height + dragged.height
        )
        let ratio = scale / zoom
        guard ratio != 1, let anchor = pointerAt else { return dragging }
        let away = CGPoint(x: anchor.x - centre.x, y: anchor.y - centre.y)
        return CGSize(
            width: away.x * (1 - ratio) + dragging.width * ratio,
            height: away.y * (1 - ratio) + dragging.height * ratio
        )
    }

    /// Take the camera back at wherever it is on screen, abandoning where it was going.
    ///
    /// Called by anything that touches the field. Evaluating the same `UnitCurve` the flight
    /// was given, at the elapsed fraction, is where the screen is — so the value it commits
    /// is the one already being looked at and nothing moves at the moment of the catch.
    private func catchCamera() {
        guard let inFlight = flight else { return }
        flight = nil
        let elapsed = Date().timeIntervalSince(inFlight.started)
        guard inFlight.seconds > 0, elapsed < inFlight.seconds else { return }
        let k = CGFloat(
            Design.Motion.easeOutCubic.value(at: max(0, elapsed / inFlight.seconds))
        )
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            offset = CGSize(
                width: inFlight.fromOffset.width
                    + (inFlight.toOffset.width - inFlight.fromOffset.width) * k,
                height: inFlight.fromOffset.height
                    + (inFlight.toOffset.height - inFlight.fromOffset.height) * k
            )
            zoom = inFlight.fromZoom + (inFlight.toZoom - inFlight.fromZoom) * k
        }
    }

    /// The magnification, as a whole percentage. Built as a `String` rather than
    /// interpolated: `Text` would group-separate it, and "1,000%" is not a thing.
    private var zoomLabel: String { "\(Int((scale * 100).rounded()))%" }

    /// Zoom about the middle of the view.
    ///
    /// Zoom about a point, which is the middle of the view unless somebody says otherwise.
    ///
    /// `away` is how far the anchor sits from the centre. Zero is the reference's own
    /// behaviour for its zoom buttons — a press of a button is not aimed at anything, so the
    /// middle is the only fair place to keep still. A scroll *is* aimed: the reference keeps
    /// the memory under the cursor exactly where it is, and this port had been pinning the
    /// centre instead, so zooming toward a node slid it away from you.
    private func zoom(by factor: CGFloat, away: CGPoint = .zero, animated: Bool = true) {
        catchCamera()
        let target = min(
            max(zoom * factor, Design.Layout.canvasMinZoom), Design.Layout.canvasMaxZoom
        )
        guard target != zoom else { return }
        let ratio = target / zoom
        let apply = {
            offset.width = away.x * (1 - ratio) + offset.width * ratio
            offset.height = away.y * (1 - ratio) + offset.height * ratio
            zoom = target
        }
        // A press of a button is a journey and gets the camera's easing. A scroll is the
        // hand moving and gets nothing: easing a gesture that is still happening is the
        // camera arguing with the fingers, which is the reference's split too.
        if animated {
            withAnimation(motion.animation(Design.Motion.camera(Design.Motion.cameraZoomSeconds))) {
                apply()
            }
        } else {
            apply()
        }
    }

    /// Zoom the field by scrolling over it.
    ///
    /// A local monitor rather than a gesture, because SwiftUI has no scroll-wheel gesture and
    /// the field is a `Canvas` rather than a scroll view. The cost of a monitor is that it
    /// sees *every* scroll in the app, and this one used to swallow all of them — the comment
    /// here said "this surface has nothing else that scrolls", which was wrong the day it was
    /// written and got worse: the timeline panel sits beside the field with a list in it, and
    /// the command palette opens over the top of everything. Neither could be scrolled while
    /// Canvas was the current surface, by mouse or by trackpad.
    ///
    /// So it acts only while the pointer is actually over the field, and passes every other
    /// scroll along untouched. Hover is the right test rather than the pointer's coordinates:
    /// SwiftUI stops reporting the field as hovered the moment something is layered over it,
    /// which is exactly the case the coordinates would get wrong.
    private func watchScrollWheel() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            let delta = event.scrollingDeltaY
            guard !paletteIsOpen, pointerInField, delta != 0 else { return event }
            stopTour()
            stopGlide()
            // Trackpad: continuous, so the exponential the reference uses, which keeps each
            // unit of movement worth the same *ratio* however far in you already are.
            // Wheel: one firm notch, because a mouse has no in-between to offer.
            let factor = event.hasPreciseScrollingDeltas
                ? exp(delta * Design.Layout.canvasWheelSensitivity)
                : (delta > 0
                    ? Design.Layout.canvasWheelStep
                    : 1 / Design.Layout.canvasWheelStep)
            // Anchored on the pointer, which is what makes zooming *toward* something work:
            // the reference keeps the memory under the cursor exactly where it is.
            zoom(by: factor, away: pointerAway, animated: !event.hasPreciseScrollingDeltas)
            // Swallowed only now that it has been used for something.
            return nil
        }
    }

    /// A click: select, or focus when it is the second on the same node.
    ///
    /// Double-click is timed rather than declared, because declaring one made SwiftUI hold
    /// every single click back to see whether a second was coming — exactly the hesitation
    /// this surface should not have.
    private func click(at location: CGPoint, centre: CGPoint) {
        stopTour()
        stopGlide()
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
        stopTour()
        centre(
            on: node.id,
            zoom: Design.Layout.canvasFocusZoom,
            seconds: Design.Motion.cameraCentreSeconds
        ) { select(node) }
    }

    /// Fly the camera until one node is in the middle at a given magnification.
    ///
    /// The whole of the camera goes through here — focusing, and every stop of a tour — so
    /// there is one place that decides what a journey looks like.
    private func centre(
        on id: String,
        zoom target: CGFloat,
        seconds: TimeInterval,
        then also: (() -> Void)? = nil
    ) {
        guard let point = canvas.positions[id] else { return }
        stopGlide()
        catchCamera()
        let landing = CGSize(width: -point.x * target, height: -point.y * target)
        flight = Flight(
            fromOffset: offset, toOffset: landing,
            fromZoom: zoom, toZoom: target,
            started: Date(), seconds: motion.reduced ? 0 : seconds
        )
        withAnimation(motion.animation(Design.Motion.camera(seconds))) {
            zoom = target
            offset = landing
            dragged = .zero
            also?()
        }
    }

    /// Lean the camera a little way toward where it is going next.
    ///
    /// Linear rather than eased, and that is deliberate: an ease would have a shape, and a
    /// shape is a movement you notice. A constant crawl is the camera being held rather than
    /// being moved, which is the difference this is for.
    private func drift(from stop: String, toward next: String, over seconds: TimeInterval) {
        guard seconds > 0, !motion.reduced,
              let here = canvas.positions[stop], let there = canvas.positions[next] else { return }
        let share = Design.Motion.tourDriftShare
        let target = CGPoint(
            x: here.x + (there.x - here.x) * share,
            y: here.y + (there.y - here.y) * share
        )
        withAnimation(Design.Motion.drift(seconds)) {
            offset = CGSize(width: -target.x * zoom, height: -target.y * zoom)
        }
    }

    /// Replay Story: the camera travels through a memory and the things around it, dwelling
    /// on each. Narration by motion — there are no words, and it does not need any.
    ///
    /// The stops come from ``CanvasGraph/tourPath(from:limit:)`` so the ordering is the
    /// reference's and lives somewhere it can be tested. What is here is only the flying:
    /// rest on a stop, move to the next, and when the last one is done let it go.
    private func startTour(from node: CanvasGraph.Node) {
        stopTour()
        select(node)
        let path = canvas.graph.tourPath(from: node.id)
        let flight = Design.Motion.tourCameraSeconds
        let held = max(0, Design.Motion.tourDwellSeconds - flight)
        tour = Task { @MainActor in
            for (index, stop) in path.enumerated() {
                let isEnd = index == 0 || index == path.count - 1
                tourFrom = index == 0 ? nil : path[index - 1]
                tourArrivedAt = Date()
                withAnimation(motion.animation(Design.Motion.inPlace)) { tourStop = stop }
                centre(
                    on: stop,
                    zoom: isEnd
                        ? Design.Layout.canvasTourEndZoom
                        : Design.Layout.canvasTourStepZoom,
                    seconds: flight
                )

                // The flight, then the rest of the dwell — spent leaning toward wherever the
                // camera is going next rather than sitting still, so the story is one
                // movement instead of a run of separate ones.
                try? await Task.sleep(for: .seconds(flight))
                if Task.isCancelled { return }
                if index + 1 < path.count {
                    drift(from: stop, toward: path[index + 1], over: held)
                }
                try? await Task.sleep(for: .seconds(held))
                if Task.isCancelled { return }
            }
            // One last dwell on the way home, so the story ends on the thing it was about
            // rather than snapping out the instant the camera lands.
            try? await Task.sleep(for: .seconds(Design.Motion.tourDwellSeconds))
            if Task.isCancelled { return }
            withAnimation(motion.animation(Design.Motion.inPlace)) { tourStop = nil }
            tourFrom = nil
            tour = nil
        }
    }

    /// Stop the tour wherever it is. Called by anything that touches the field, because a
    /// camera that carries on while you are dragging is a camera you are fighting.
    private func stopTour() {
        guard tour != nil || tourStop != nil else { return }
        tour?.cancel()
        tour = nil
        tourFrom = nil
        withAnimation(motion.animation(Design.Motion.inPlace)) { tourStop = nil }
    }

    /// How far through the current stop the story is, on two clocks.
    ///
    /// `flight` runs while the camera is travelling and draws the line; `breath` runs a
    /// little longer and is the ring the stop lets out on arrival. Both eased out, so each
    /// starts quickly and settles rather than running at a constant rate — a line that
    /// creeps at a fixed speed reads as a progress bar.
    /// Both finished is how "draw neither" is said: the line and the breath are only drawn
    /// while their phase is under 1, so reduced motion keeps the camera and the lit stop and
    /// silently drops the decoration.
    private func tourPhase(at now: Date) -> (flight: CGFloat, breath: CGFloat) {
        guard !motion.reduced else { return (1, 1) }
        let elapsed = now.timeIntervalSince(tourArrivedAt)
        return (
            easedOut(elapsed, over: Design.Motion.tourCameraSeconds),
            easedOut(elapsed, over: Design.Motion.tourBreathSeconds)
        )
    }

    /// How far the selection's halo has arrived.
    private func arrival(at now: Date) -> CGFloat {
        guard !motion.reduced else { return 1 }
        return easedOut(
            now.timeIntervalSince(selectedAt), over: Design.Motion.selectionArriveSeconds
        )
    }

    /// Fast to most of the way, then settling — the shape everything in this file that is
    /// driven off a clock rather than by SwiftUI uses.
    private func easedOut(_ elapsed: TimeInterval, over seconds: TimeInterval) -> CGFloat {
        let t = CGFloat(min(1, max(0, elapsed / seconds)))
        return 1 - pow(1 - t, 3)
    }

    /// A flick keeps gliding, decaying to rest — movement with momentum.
    ///
    /// The reference multiplies the speed by ``Design/Layout/canvasGlideDecay`` once per
    /// animation frame, which ties how far a flick coasts to the display's refresh rate.
    /// That is a quirk rather than a decision, so this reads the same number as the rate it
    /// was written against and decays by elapsed time instead — the same glide on a 60 Hz
    /// display and on a 120 Hz one.
    ///
    /// Its two thresholds are per-frame distances upstream for the same reason, so they are
    /// read at that rate too: "faster than 2 points a frame" is 120 points a second, which
    /// is what SwiftUI hands over.
    private func startGlide(velocity: CGSize) {
        stopGlide()
        let hz = Design.Layout.canvasGlideReferenceHz
        let speed = hypot(velocity.width, velocity.height)
        guard speed > Design.Layout.canvasGlideMinSpeed * hz, !motion.reduced else { return }
        let rest = Design.Layout.canvasGlideRestSpeed * hz
        glide = Task { @MainActor in
            var current = velocity
            var last = ContinuousClock.now
            while !Task.isCancelled, hypot(current.width, current.height) > rest {
                try? await Task.sleep(for: .seconds(1 / hz))
                if Task.isCancelled { return }
                let now = ContinuousClock.now
                let tick = now - last
                last = now
                let elapsed = CGFloat(
                    Double(tick.components.seconds) + Double(tick.components.attoseconds) * 1e-18
                )
                offset.width += current.width * elapsed
                offset.height += current.height * elapsed
                let kept = pow(Design.Layout.canvasGlideDecay, elapsed * hz)
                current.width *= kept
                current.height *= kept
            }
            glide = nil
        }
    }

    private func stopGlide() {
        glide?.cancel()
        glide = nil
    }

    private func select(_ node: CanvasGraph.Node?) {
        if node?.id != selected?.id { selectedAt = Date() }
        selected = node
        neighbourhood = node.map { canvas.graph.neighbours(of: $0.id) } ?? []
    }

    /// Where a point sits once the field's own sway is taken into account.
    ///
    /// Used by the drawing *and* by the hit test, which is the whole reason it is a function
    /// rather than two copies of the same arithmetic: a field that moves under a click the
    /// eye had already aimed is worse than a field that does not move at all.
    private func sway(_ point: CGPoint, at now: Date) -> CGPoint {
        guard !motion.reduced else { return point }
        let t = now.timeIntervalSinceReferenceDate
        let angle = Design.Motion.canvasSwayDegrees * .pi / 180
            * sin(t * 2 * .pi / Design.Motion.canvasSwaySeconds)
        let wander = t * 2 * .pi / Design.Motion.canvasDriftSeconds
        let cosine = cos(angle)
        let sine = sin(angle)
        return CGPoint(
            x: point.x * cosine - point.y * sine
                + Design.Motion.canvasDriftPoints * cos(wander),
            // Half the reach vertically: the field is wider than it is tall, and an equal
            // wander in both reads as a wobble rather than as a drift.
            y: point.x * sine + point.y * cosine
                + Design.Motion.canvasDriftPoints * sin(wander) / 2
        )
    }

    /// How strongly a node reads right now.
    ///
    /// Focus is a *dimming*, not a hiding: the rest of the field stays visible so the thing
    /// you focused is still somewhere, rather than alone on an empty page. Everything at
    /// full weight when nothing is selected, which is the ordinary state.
    private func emphasis(_ node: CanvasGraph.Node) -> Double {
        var weight = 1.0
        // Pull the applications back once the field is far enough out that they have stopped
        // being the point. What is left holding the picture is what was built on them.
        if node.type == .app, scale < Design.Layout.canvasAppsFadedBelowZoom {
            weight = Design.Colour.canvasAppFaded
        }
        guard focusMode, selected != nil else { return weight }
        return neighbourhood.contains(node.id) ? weight : min(weight, Design.Colour.canvasUnfocused)
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if canvas.loaded && canvas.graph.nodes.isEmpty {
                    empty.centredInPage()
                } else {
                    field
                    if let selected { preview(selected) }
                    // Opposite corner to the card, so the thing that undoes a focus is not
                    // sitting among the things that act on it.
                    if selected != nil {
                        clearFocus
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .transition(motion.transition(.opacity))
                    }
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
        .onAppear {
            paletteIsOpen = paletteOpen
            watchScrollWheel()
        }
        .onChange(of: paletteOpen) { _, now in paletteIsOpen = now }
        .onDisappear {
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
            scrollMonitor = nil
            // Both keep moving the camera on their own, so both have to go with the view —
            // a tour still flying against a surface nobody is looking at is work for nothing
            // and a field in the wrong place when you come back.
            stopTour()
            stopGlide()
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
                    stopTour()
                    stopGlide()
                    withAnimation(motion.animation(Design.Motion.camera(
                        Design.Motion.cameraSeconds
                    ))) {
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
                    stopTour()
                    stopGlide()
                    withAnimation(motion.animation(Design.Motion.camera(
                        Design.Motion.cameraSeconds
                    ))) {
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
                            // Caught before the first pixel of drag is applied, so what the
                            // translation is added to is where the camera is rather than
                            // where it was headed.
                            if !dragging { stopTour(); stopGlide(); catchCamera() }
                            dragging = true
                            dragged = value.translation
                        }
                    }
                    .onEnded { value in
                        if dragging {
                            offset.width += value.translation.width
                            offset.height += value.translation.height
                            dragging = false
                            dragged = .zero
                            // Let go mid-movement and the field keeps going. `velocity` is
                            // already points per second, which is what the glide wants.
                            startGlide(velocity: value.velocity)
                            return
                        }
                        click(at: value.location, centre: centre)
                        dragging = false
                        dragged = .zero
                    }
            )
            .gesture(
                MagnifyGesture()
                    .onChanged {
                        if pinch == 1 { stopTour(); stopGlide(); catchCamera() }
                        pinch = $0.magnification
                    }
                    .onEnded { value in
                        // Commit exactly what was being drawn: the same anchored offset the
                        // gesture was showing, so letting go changes nothing on screen.
                        let settled = liveOffset(centre: centre)
                        let target = min(
                            max(zoom * value.magnification, Design.Layout.canvasMinZoom),
                            Design.Layout.canvasMaxZoom
                        )
                        offset = CGSize(
                            width: settled.width - dragged.width,
                            height: settled.height - dragged.height
                        )
                        zoom = target
                        pinch = 1
                    }
            )
            .accessibilityHidden(true)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                fieldCentre = CGPoint(x: size.width / 2, y: size.height / 2)
            }
            .onContinuousHover { phase in
                if case .active(let location) = phase {
                    pointerInField = true
                    pointerAt = location
                    // Not while dragging: the field is moving under the pointer then, and a
                    // node lighting up because it happened to slide beneath it is noise.
                    let under = dragging ? nil : node(at: location, centre: fieldCentre)?.id
                    if under != hovered {
                        withAnimation(motion.animation(Design.Motion.inPlace)) { hovered = under }
                    }
                } else {
                    pointerInField = false
                    if hovered != nil {
                        withAnimation(motion.animation(Design.Motion.inPlace)) { hovered = nil }
                    }
                    // Deliberately kept: a pinch begins after the cursor has stopped moving,
                    // and on a trackpad it does not move during one. The last place it was
                    // is the anchor the gesture is aimed at.
                }
            }
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
        // On a clock while the field is arriving *or* while a story is playing, and off it
        // otherwise — a timeline still ticking with nothing moving is a redraw a second for
        // nothing. Reduced motion keeps the camera and the lit stop, which are what the
        // feature *is*, and drops the line and the breath, which are decoration.
        if motion.reduced {
            // Nothing moves on its own, so nothing needs a clock. The field is still drawn
            // in full — reduced motion asks for less movement, not for less of the picture.
            renderField(centre: centre, progress: 1, now: .distantFuture)
        } else if entranceDone && tour == nil {
            // Only the sway is running, and it is slow enough that a third of a display's
            // rate is indistinguishable from all of it. Qualified: this app has its own
            // `TimelineView` — the Timeline surface — and it shadows SwiftUI's here.
            SwiftUI.TimelineView(
                .periodic(from: entranceStart, by: Design.Motion.canvasAmbientTick)
            ) { timeline in
                renderField(centre: centre, progress: 1, now: timeline.date)
            }
        } else {
            // The entrance or a story is playing, and both are movement worth every frame.
            SwiftUI.TimelineView(.animation) { timeline in
                renderField(
                    centre: centre, progress: progress(at: timeline.date), now: timeline.date
                )
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
    private func renderField(centre: CGPoint, progress: CGFloat, now: Date) -> some View {
        let phase = tourPhase(at: now)
        let camera = liveOffset(centre: centre)
        // Built once a frame rather than searched per edge. The field redraws continuously
        // now that it sways, and an edge asking the node list for each of its ends turns a
        // few hundred lines into tens of thousands of comparisons a second for nothing.
        let byID = Dictionary(
            canvas.graph.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        return Canvas { context, _ in
                func weight(of id: String) -> Double {
                    guard let node = byID[id] else { return 1 }
                    return emphasis(node)
                }
                func place(_ point: CGPoint) -> CGPoint {
                    let swayed = sway(point, at: now)
                    return CGPoint(
                        x: centre.x + (swayed.x * scale) + camera.width,
                        y: centre.y + (swayed.y * scale) + camera.height
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
                    let lit = min(weight(of: edge.a), weight(of: edge.b))
                    let weight: Double = (Design.Colour.canvasEdgeFloor
                        + strength * Design.Colour.canvasEdgeRange) * Double(progress) * lit
                    context.stroke(
                        path,
                        with: .color(.secondary.opacity(weight)),
                        lineWidth: Design.Layout.canvasEdgeWidth
                    )
                }

                // The line the camera is on, drawn over the edges and under the nodes so it
                // reads as one of the field's own lines rather than as an overlay. Drawn
                // only as far as the camera has flown, which is what makes it look like the
                // story travelling rather than a connection being pointed at.
                if let tourFrom, let tourStop,
                   let from = canvas.positions[tourFrom], let to = canvas.positions[tourStop],
                   phase.flight < 1 {
                    let start = place(from)
                    let end = place(to)
                    var path = Path()
                    path.move(to: start)
                    path.addLine(
                        to: CGPoint(
                            x: start.x + (end.x - start.x) * phase.flight,
                            y: start.y + (end.y - start.y) * phase.flight
                        )
                    )
                    context.stroke(
                        path,
                        with: .color(tint.opacity(Design.Colour.canvasTourPath)),
                        style: StrokeStyle(
                            lineWidth: Design.Layout.canvasRingWidth, lineCap: .round
                        )
                    )
                }

                for node in canvas.graph.nodes {
                    guard let point = canvas.positions[node.id] else { continue }
                    let grown = entrance(node, progress)
                    if grown <= 0.001 { continue }
                    let at = place(point)
                    let radius = self.radius(for: node) * scale * grown
                    context.opacity = emphasis(node)
                    let box = CGRect(
                        x: at.x - radius, y: at.y - radius, width: radius * 2, height: radius * 2
                    )

                    // Every node is a bubble with something inside it, and the something
                    // has room around it. Before, an icon was clipped to the full circle:
                    // a macOS icon is a squircle, so its corners were cut off, and a
                    // collection's glyph ran edge to edge into its own ring. Inset, both
                    // read as a thing *in* a bubble rather than a thing cropped by one.
                    let inner = box.insetBy(
                        dx: radius * Design.Layout.canvasIconInset,
                        dy: radius * Design.Layout.canvasIconInset
                    )
                    // The bubble is quieter behind an icon than behind a glyph: the ring
                    // already says what kind of thing this is, and a saturated disc under
                    // every application read as a halo rather than as padding.
                    let hasIcon = iconKey(for: node) != nil
                    // Active is the reference's one word for three things: the node you
                    // focused, the stop a story is resting on, and the node under the
                    // pointer. They read alike because they mean alike — this is the one
                    // being talked about.
                    let isActive = node.id == selected?.id
                        || node.id == tourStop
                        || node.id == hovered
                    context.fill(
                        Circle().path(in: box),
                        with: .color(
                            hasIcon
                                ? colour(for: node).opacity(
                                    isActive
                                        ? Design.Colour.canvasBubbleActive
                                        : Design.Colour.canvasBubbleBehindIcon
                                )
                                : colour(for: node)
                        )
                    )

                    // A field of real icons is recognisable at a glance in a way a field of
                    // coloured dots never is. Ringed, so the node's *kind* survives wearing
                    // another thing's face — a project built on Terminal must not read as
                    // Terminal.
                    let icon = radius >= Design.Layout.canvasIconThreshold
                        ? iconKey(for: node).flatMap { context.resolveSymbol(id: "icon:\($0)") }
                        : nil
                    if let icon {
                        context.drawLayer { layer in
                            // A squircle, not a circle: it is the shape the icon was drawn
                            // as, and clipping a squircle to a circle is what took the
                            // corners off in the first place.
                            layer.clip(to: RoundedRectangle(
                                cornerRadius: inner.width * Design.Radius.iconSquircleRatio,
                                style: .continuous
                            ).path(in: inner))
                            layer.draw(icon, in: inner)
                        }
                    } else if node.type == .collection,
                              radius >= Design.Layout.canvasIconThreshold,
                              let glyph = context.resolveSymbol(id: "collection:\(node.ref)") {
                        // A collection has no application behind it, so it wears the glyph
                        // it wears everywhere else in the app.
                        context.draw(glyph, in: inner)
                    }

                    context.stroke(
                        Circle().path(in: box),
                        with: .color(ring(for: node)),
                        // An active node wears the heavier ring whatever it is. The
                        // reference thickens by half and this port already has the two
                        // widths in that ratio, so the strong one *is* the active one.
                        lineWidth: node.type == .app && !isActive
                            ? Design.Layout.canvasRingWidth
                            : Design.Layout.canvasRingWidthStrong
                    )

                    // A project or a chapter is wearing its lead application's face, so it
                    // says what it *is* in the corner. An application needs no badge: its
                    // own icon is already the whole answer.
                    if icon != nil, let badge = badgeSymbol(for: node),
                       radius >= Design.Layout.canvasBadgeRadius * 2,
                       let glyph = context.resolveSymbol(id: "badge:\(badge)") {
                        let size = Design.Layout.canvasBadgeRadius
                        let corner = CGPoint(x: box.maxX - size * 0.7, y: box.maxY - size * 0.7)
                        let disc = CGRect(
                            x: corner.x - size, y: corner.y - size,
                            width: size * 2, height: size * 2
                        )
                        context.fill(Circle().path(in: disc), with: .color(ring(for: node)))
                        context.draw(glyph, at: corner, anchor: .center)
                    }

                    // The selection wears a halo, and so does whichever stop a tour is
                    // resting on — the reference lights the two the same way, which is what
                    // makes a tour read as the camera pointing rather than as it drifting.
                    if node.id == selected?.id || node.id == tourStop {
                        // Eased outward from the node's own edge into its place, so the
                        // halo arrives with the click rather than being there before the
                        // eye gets back. A tour's stop skips it: the breath is already
                        // saying the same thing, and two rings arriving at once is a fuss.
                        let arrived = node.id == tourStop ? 1 : arrival(at: now)
                        let reach = Design.Layout.canvasSelectionInset * arrived
                        context.stroke(
                            Circle().path(in: box.insetBy(dx: -reach, dy: -reach)),
                            with: .color(.primary.opacity(Double(arrived))),
                            lineWidth: Design.Layout.canvasSelectionWidth
                        )
                    }

                    // The breath: one ring easing outward from the stop and fading as it
                    // goes, let out on arrival and finished well before the camera leaves.
                    // It is what tells you which of the two haloed nodes is being spoken
                    // about — the selection keeps its halo the whole way through.
                    if node.id == tourStop, phase.breath < 1 {
                        let reach = radius * Design.Motion.tourBreathReach * phase.breath
                        context.stroke(
                            Circle().path(in: box.insetBy(dx: -reach, dy: -reach)),
                            with: .color(
                                tint.opacity(
                                    Design.Colour.canvasTourBreath * (1 - Double(phase.breath))
                                )
                            ),
                            lineWidth: Design.Motion.tourBreathWidth
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
                // Whatever is being talked about goes first, so it claims its name before
                // anything else can crowd it out.
                let speaking: (CanvasGraph.Node) -> Bool = {
                    $0.id == selected?.id || $0.id == hovered || $0.id == tourStop
                }
                // Upstream's `labelVisible`, which this port never had. An application or a
                // moment only gets its name once the field is far enough in to have room for
                // it; everything built on them — collections, projects, chapters — is named
                // at every zoom, because those names are the map. Whatever is being talked
                // about is named regardless.
                //
                // The collision test below is this port's own and stays: it decides which of
                // two names that would overlap survives, which is a question the reference
                // never has to answer because it does not place labels greedily.
                let named: (CanvasGraph.Node) -> Bool = { node in
                    if speaking(node) { return true }
                    switch node.type {
                    case .app, .moment: return scale >= Design.Layout.canvasAppLabelsFromZoom
                    default: return true
                    }
                }
                let ordered = canvas.graph.nodes
                    .filter(speaking)
                    + canvas.graph.nodes
                        .filter { !speaking($0) }
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
                    // An active node always keeps its label, which is upstream's
                    // `labelVisible` rule and the whole reason hover is worth having: it is
                    // how you read a crowded node's name without clicking it.
                    guard named(node) else { continue }
                    if !speaking(node) && placed.contains(where: { $0.intersects(box) }) {
                        continue
                    }
                    placed.append(box)
                    context.opacity = emphasis(node)
                    context.draw(text, at: origin, anchor: .topLeading)
                    context.opacity = 1
                }
            } symbols: {
                // Declared once at a fixed size and resolved per frame from the cache, so
                // panning does not re-rasterise anything. Only nodes that actually have an
                // application behind them appear here; the rest fall back to a dot.
                ForEach(iconKeys, id: \.self) { key in
                    AppIcon(
                        bundleID: iconSources[key]?.bundleID,
                        appPath: iconSources[key]?.appPath,
                        size: Design.Layout.canvasSymbolSize
                    )
                    .tag("icon:\(key)")
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
        .buttonStyle(.row)
        .accessibilityHint("Opens the day this happened on")
    }

    /// The way back to the whole field.
    ///
    /// The toolbar's recentre button already does this and more — it also returns the zoom
    /// and the position to where they started. This is the smaller, more obvious thing: it
    /// drops the focus and lets everything that was pulled back come forward again, without
    /// moving the camera. Having focused something and read it, the next thing anybody wants
    /// is the rest of the picture, and the reference puts that within reach rather than in a
    /// toolbar at the far end of the window.
    private var clearFocus: some View {
        Button {
            stopTour()
            withAnimation(motion.animation(Design.Motion.settle)) { select(nil) }
        } label: {
            Label("Clear focus", systemImage: "xmark")
                .font(Design.Text.detail)
        }
        .buttonStyle(.bordered)
        .keyboardShortcut(.escape, modifiers: [])
        .help("Bring the whole field back")
        .padding(Design.Space.page)
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
            HStack(spacing: Design.Space.inline) {
                if node.ref.isEmpty {
                    Text("Nothing to open for this one.")
                        .font(Design.Text.micro)
                        .foregroundStyle(.tertiary)
                } else {
                    Button {
                        onOpen(node)
                    } label: {
                        Label("Open", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.borderedProminent)
                }

                // The way to be *told* about a memory rather than to go and read it: the
                // camera walks the things around it and rests on each. Offered here and
                // nowhere else, because it only means anything once the field has been
                // narrowed to one memory — which is what focusing did.
                Button {
                    if tour == nil { startTour(from: node) } else { stopTour() }
                } label: {
                    Label(
                        tour == nil ? "Replay Story" : "Stop",
                        systemImage: tour == nil ? "play" : "stop"
                    )
                }
                .buttonStyle(.bordered)
                .help(
                    tour == nil
                        ? "Travel through this and the things around it"
                        : "Stop the story"
                )
            }
            .padding(.top, Design.Space.tight)
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
    /// What identifies a node's icon, rather than the node.
    ///
    /// Several nodes wear the same face — an application, the projects built on it, the
    /// chapters those belong to. Rasterising per *node* drew the same icon a dozen times at
    /// full size; keyed on the icon there is one of each.
    private func iconKey(for node: CanvasGraph.Node) -> String? {
        node.bundleID ?? node.appPath
    }

    /// Every distinct icon in the field, and somewhere to resolve each from.
    private var iconSources: [String: (bundleID: String?, appPath: String?)] {
        var found: [String: (bundleID: String?, appPath: String?)] = [:]
        for node in canvas.graph.nodes {
            guard let key = iconKey(for: node), found[key] == nil else { continue }
            found[key] = (node.bundleID, node.appPath)
        }
        return found
    }

    private var iconKeys: [String] { iconSources.keys.sorted() }

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
        case .project: tint
        case .chapter: .orange
        case .moment: .yellow
        case .collection: tint
        }
    }

    private func colour(for node: CanvasGraph.Node) -> Color {
        switch node.type {
        case .collection: tint
        case .project: tint.opacity(Design.Colour.canvasProjectOpacity)
        case .chapter: .orange.opacity(Design.Colour.canvasChapterOpacity)
        case .moment: .yellow.opacity(Design.Colour.canvasMomentOpacity)
        case .app: .secondary.opacity(Design.Colour.canvasAppOpacity)
        }
    }

    /// The node under a click, nearest first — with a little slack, so a small star does not
    /// demand a pixel-perfect hit.
    private func node(at location: CGPoint, centre: CGPoint) -> CanvasGraph.Node? {
        var best: (node: CanvasGraph.Node, distance: CGFloat)?
        // Read at the moment of the click rather than off the drawing's clock — the two are
        // at most a frame apart, and at this speed a frame is a fraction of a point.
        let now = Date()
        let camera = liveOffset(centre: centre)
        for node in canvas.graph.nodes {
            guard let point = canvas.positions[node.id] else { continue }
            let swayed = sway(point, at: now)
            let at = CGPoint(
                x: centre.x + swayed.x * scale + camera.width,
                y: centre.y + swayed.y * scale + camera.height
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
