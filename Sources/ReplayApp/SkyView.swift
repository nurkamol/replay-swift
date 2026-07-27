import ReplayCore
import SwiftUI

/// The sky at a given hour.
///
/// A day has a shape, and it is not the same shape at four in the morning as at four in the
/// afternoon. This gives a surface that reads back a moment somewhere to *be* — late night is
/// deep and cold, dawn warms at the horizon, midday is open, evening closes again.
///
/// It is not decoration for its own sake: on Replay Day it follows the playhead, so watching
/// a day back visibly passes through it, and on Today it follows the actual hour, so the
/// headline sits in the part of the day it is describing. Everything here is derived from the
/// clock and nothing from the data — the app has no opinion about the hours themselves.
struct Sky: View {
    /// The instant to draw. Interpolated between the anchor hours rather than switched at
    /// them, so nothing ever jumps between two adjacent minutes.
    let at: Int64
    /// How strongly it reads. A full-window film can carry more than a card can.
    var strength: Double = 1

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        // Reduce Transparency means "stop putting things behind my content"; a shifting
        // gradient under text is exactly that, so it becomes a flat surface.
        let colours = reduceTransparency ? [flat, flat] : palette
        LinearGradient(
            colors: colours,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .opacity(reduceTransparency ? 1 : strength)
        .animation(.easeInOut(duration: Design.Motion.skySeconds), value: hourFraction)
    }

    private var flat: Color { scheme == .dark ? .black : Color(white: 0.96) }

    /// The hour, with its minutes, as a fraction of the day.
    private var hourFraction: Double {
        let date = Date(timeIntervalSince1970: Double(at) / 1000)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60) / 24
    }

    /// Four anchors around the day, blended between.
    ///
    /// Deliberately desaturated: this sits behind text that has to stay readable, and a sky
    /// that competes with the words on it has stopped being a background.
    private var palette: [Color] {
        let stops: [(at: Double, top: Color, bottom: Color)] = scheme == .light
            ? [
                (0.0, Color(red: 0.72, green: 0.75, blue: 0.85), Color(red: 0.86, green: 0.87, blue: 0.92)),
                (0.27, Color(red: 0.98, green: 0.87, blue: 0.80), Color(red: 0.94, green: 0.90, blue: 0.88)),
                (0.52, Color(red: 0.85, green: 0.91, blue: 0.98), Color(red: 0.95, green: 0.96, blue: 0.98)),
                (0.80, Color(red: 0.93, green: 0.85, blue: 0.86), Color(red: 0.88, green: 0.87, blue: 0.92)),
            ]
            : [
                // Late night: cold and nearly out.
                (0.0, Color(red: 0.05, green: 0.06, blue: 0.11), Color(red: 0.02, green: 0.02, blue: 0.04)),
                // Dawn: warmth arriving at the bottom of the frame.
                (0.27, Color(red: 0.16, green: 0.11, blue: 0.14), Color(red: 0.24, green: 0.14, blue: 0.11)),
                // Midday: open, and the coolest of the four.
                (0.52, Color(red: 0.09, green: 0.13, blue: 0.20), Color(red: 0.05, green: 0.08, blue: 0.13)),
                // Evening: closing, warmer again.
                (0.80, Color(red: 0.15, green: 0.09, blue: 0.16), Color(red: 0.07, green: 0.05, blue: 0.09)),
            ]

        let f = hourFraction
        // Wrapped, so 23:00 blends toward midnight rather than falling off the end.
        var lower = stops.last!
        var upper = stops.first!
        var lowerAt = stops.last!.at - 1
        var upperAt = stops.first!.at
        for (index, stop) in stops.enumerated() where stop.at <= f {
            lower = stop
            lowerAt = stop.at
            let next = index + 1 < stops.count ? stops[index + 1] : stops[0]
            upper = next
            upperAt = index + 1 < stops.count ? next.at : 1
        }
        let width = max(0.0001, upperAt - lowerAt)
        let t = min(1, max(0, (f - lowerAt) / width))
        return [lower.top.mix(with: upper.top, by: t), lower.bottom.mix(with: upper.bottom, by: t)]
    }
}
