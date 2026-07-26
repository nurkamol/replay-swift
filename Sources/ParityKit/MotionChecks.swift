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
}
