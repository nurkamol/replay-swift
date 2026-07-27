import Foundation

/// The motion tokens, as plain numbers.
///
/// `ParityKit` cannot import the app target — `ReplayApp` is an executable — so the design
/// system's motion values are mirrored here and checked against `spec/constants.json`, the
/// same way `Rules` is. Two copies on purpose, and a check that keeps them equal: the
/// shipping app should not parse JSON to know how fast a card opens.
///
/// If this file and `Design.Motion` disagree, the app is right and this is stale — but the
/// suite will say so, which is the point.
public enum MotionTokens {
    public static let pressSeconds: Double = 0.090
    public static let hoverSeconds: Double = 0.180
    public static let enterSeconds: Double = 0.460
    public static let easeSoft: [Double] = [0.16, 1, 0.3, 1]
    public static let easeStandard: [Double] = [0.32, 0.72, 0, 1]
    public static let staggerSeconds: Double = 0.028
    public static let staggerCapSeconds: Double = 0.560
    /// A search result's own stagger, which is deliberately not the one above — see
    /// `Design.Motion.resultStaggerSeconds`.
    public static let resultStaggerSeconds: Double = 0.010
    public static let resultStaggerCapSeconds: Double = 0.220
}

/// The canvas camera, as plain numbers, mirroring `Design.Layout` and `Design.Motion`.
///
/// Same arrangement and same reason as ``MotionTokens``. This half went unchecked for
/// longer, and five of these had quietly drifted from the reference — the focus zoom, how
/// far out the field would go, the size of a step of zoom, the easing, and the fact that a
/// flick used to stop dead here and glides upstream. Nothing caught it, because
/// `port-queue.mjs` can say a view changed and cannot say what it now does.
public enum CanvasTokens {
    /// The tour: how long it rests on each stop, how many neighbours it visits, how long
    /// the camera takes between them, and how close it gets at the ends and in the middle.
    public static let tourDwellSeconds: Double = 1.150
    public static let tourNeighbours: Int = 5
    public static let tourCameraSeconds: Double = 0.760
    public static let tourEndZoom: Double = 1.5
    public static let tourStepZoom: Double = 1.9

    /// The camera elsewhere: focusing, centring, and its own default.
    public static let focusZoom: Double = 1.55
    public static let centreZoom: Double = 1.6
    public static let centreSeconds: Double = 0.620
    public static let cameraSeconds: Double = 0.560

    /// Zoom: one press of a button, how far in and out the field goes, and the wheel.
    public static let zoomButtonStep: Double = 1.2
    public static let zoomButtonSeconds: Double = 0.340
    public static let minZoom: Double = 0.32
    public static let maxZoom: Double = 3
    public static let wheelStep: Double = 1.09
    public static let wheelSensitivity: Double = 0.012

    /// How the field itself is drawn, as opposed to how the camera moves through it. Left
    /// out when the camera was brought into the contract, and `unfocusedOpacity` had already
    /// drifted — this port dimmed to 0.14 where the reference dims to 0.1.
    public static let unfocusedOpacity: Double = 0.1
    public static let appFaded: Double = 0.32
    public static let appsFadedBelowZoom: Double = 0.7
    public static let appLabelsFromZoom: Double = 1.15

    /// The inertial glide after a flick: the speed it has to beat to start, what it keeps
    /// of that speed each frame, and the speed at which it is called finished.
    public static let glideMinSpeed: Double = 2
    public static let glideDecay: Double = 0.9
    public static let glideRestSpeed: Double = 0.4
}

/// The screensaver's drift, mirroring `Design.Motion`.
///
/// Here for the same reason the canvas camera is: `ParityKit` cannot import `ReplayApp`,
/// so a value the two apps are meant to share has to be restated somewhere the suite can
/// reach. `tools/design-audit.mjs` ties this back to `DesignSystem.swift`, which is what
/// stops the mirror and the app drifting apart while both stay green.
public enum ScreensaverTokens {
    public static let driftSeconds: Double = 90
    public static let reducedSeconds: Double = 240
    /// Ambient mode's breath — the only thing that moves on that screen.
    public static let breatheSeconds: Double = 6
    public static let breatheScale: Double = 1.04
    public static let breatheFloor: Double = 0.96
}
