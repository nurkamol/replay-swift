@testable import ReplayUI
import AppKit
import Foundation
import SwiftUI
import Testing

/// Renders the sky at every other hour to `/tmp/sky/`, so it can be *looked at*.
///
/// Not an assertion — a palette is not something a number can approve. Disabled so it does
/// not run in CI; enable it while tuning:
///
///     REPLAY_RENDER_SKY=1 swift test --filter "Sky preview"
@Suite("Sky preview", .disabled(if: ProcessInfo.processInfo.environment["REPLAY_RENDER_SKY"] == nil))
@MainActor
struct SkyPreview {
    @Test("Render the day")
    func render() throws {
        let directory = URL(fileURLWithPath: "/tmp/sky")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        for scheme in [ColorScheme.dark, .light] {
            var tiles: [(String, Image)] = []
            for hour in stride(from: 0, to: 24, by: 2) {
                var parts = DateComponents()
                parts.year = 2026
                parts.month = 7
                parts.day = 27
                parts.hour = hour
                parts.minute = 30
                let at = Int64(calendar.date(from: parts)!.timeIntervalSince1970 * 1000)

                let renderer = ImageRenderer(
                    content: Sky(at: at)
                        .frame(width: 240, height: 150)
                        .environment(\.colorScheme, scheme)
                )
                renderer.scale = 2
                if let image = renderer.nsImage {
                    tiles.append((String(format: "%02d:30", hour), Image(nsImage: image)))
                }
            }

            let sheet = VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { column in
                            let index = row * 4 + column
                            VStack(spacing: 4) {
                                tiles[index].1
                                Text(tiles[index].0)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(scheme == .dark ? .white : .black)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(scheme == .dark ? Color.black : Color.white)

            let renderer = ImageRenderer(content: sheet)
            renderer.scale = 2
            let name = scheme == .dark ? "dark.png" : "light.png"
            if let image = renderer.nsImage,
               let data = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: data),
               let png = bitmap.representation(using: .png, properties: [:])
            {
                try png.write(to: directory.appendingPathComponent(name))
            }
        }
    }
}
