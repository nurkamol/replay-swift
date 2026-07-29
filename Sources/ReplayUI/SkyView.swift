import ReplayCore
import SwiftUI

/// The sky at a given hour.
///
/// A day has a shape, and it is not the same shape at four in the morning as at eight in the
/// evening. This gives a surface that reads back a moment somewhere to *be* — night is deep
/// and cold, dawn warms at the horizon, midday is open, sunset is the warmest the app ever
/// gets, dusk closes it again.
///
/// It is not decoration for its own sake: on Replay Day it follows the playhead, so watching
/// a day back visibly passes through its own light, and on Today it follows the actual hour,
/// so the headline sits in the part of the day it is describing. Everything is derived from
/// the clock and nothing from the data — the app has no opinion about the hours themselves.
///
/// The colours live in ``Design/Sky``, anchored to the boundaries `dayPart(of:)` already
/// uses. That is deliberate: real sunset would need to know where this Mac is, and the app
/// asks for nothing. Agreeing with the label printed over it is the honest version, and it
/// is also the one that reads right — a screen saying EVENING over a black frame does not.
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
        if reduceTransparency {
            Rectangle().fill(scheme == .dark ? Design.Sky.flatDark : Design.Sky.flatLight)
        } else {
            let now = stop
            GeometryReader { geometry in
                LinearGradient(
                    colors: [now.top, now.middle, now.bottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .overlay {
                    // The light in the frame, rather than a second gradient: it moves east
                    // to west across the day and is brightest at the two edges of it, which
                    // is what makes an hour recognisable without a clock on screen.
                    RadialGradient(
                        colors: [now.glow.opacity(now.glowStrength * strength), .clear],
                        center: now.glowAt,
                        startRadius: max(geometry.size.width, geometry.size.height)
                            * Design.Sky.glowCore,
                        endRadius: max(geometry.size.width, geometry.size.height)
                            * Design.Sky.glowRadius
                    )
                }
            }
            .opacity(strength)
            .animation(.easeInOut(duration: Design.Motion.skySeconds), value: hour)
        }
    }

    /// The hour, with its minutes, on a 24-hour dial.
    private var hour: Double {
        let date = Date(timeIntervalSince1970: Double(at) / 1000)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }

    /// The two anchors this hour falls between, mixed.
    ///
    /// Wrapped, so 23:30 blends toward midnight rather than falling off the end of the
    /// table. The last anchor is at 23 rather than at 24 precisely so that wrap has a short
    /// distance to travel and midnight is not a seam.
    private var stop: Design.Sky.Stop {
        let stops = scheme == .light ? Design.Sky.light : Design.Sky.dark
        guard let first = stops.first, let last = stops.last else {
            return Design.Sky.dark[0]
        }

        let now = hour
        var lower = last
        var upper = first
        var lowerHour = last.hour - 24
        var upperHour = first.hour
        for (index, candidate) in stops.enumerated() where candidate.hour <= now {
            lower = candidate
            lowerHour = candidate.hour
            let next = index + 1 < stops.count ? stops[index + 1] : first
            upper = next
            upperHour = index + 1 < stops.count ? next.hour : first.hour + 24
        }

        let width = max(0.0001, upperHour - lowerHour)
        // Smoothed rather than linear, so an anchor is a place the sky *rests* at for a
        // while instead of a corner it turns at.
        let t = smooth(min(1, max(0, (now - lowerHour) / width)))

        return Design.Sky.Stop(
            hour: now,
            top: lower.top.mix(with: upper.top, by: t),
            middle: lower.middle.mix(with: upper.middle, by: t),
            bottom: lower.bottom.mix(with: upper.bottom, by: t),
            glow: lower.glow.mix(with: upper.glow, by: t),
            glowAt: UnitPoint(
                x: lower.glowAt.x + (upper.glowAt.x - lower.glowAt.x) * t,
                y: lower.glowAt.y + (upper.glowAt.y - lower.glowAt.y) * t
            ),
            glowStrength: lower.glowStrength
                + (upper.glowStrength - lower.glowStrength) * t
        )
    }

    private func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
}
