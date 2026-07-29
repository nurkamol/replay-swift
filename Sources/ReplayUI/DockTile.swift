import AppKit

/// Replay's Dock icon, with its own badge drawn on it.
///
/// `NSApp.dockTile.badgeLabel` looked like the obvious way to do this and is a trap: macOS
/// gates it on the notification *badge* permission for any app that links
/// `UserNotifications`, and it fails silently — the property accepts a value and reads it
/// back unchanged while the Dock draws nothing. Worse, the permission is fixed at the first
/// authorization, so an app that asked for `[.alert, .sound]` and later adds `.badge` is
/// never re-prompted and reports `notSupported` for ever. Every Mac that already said yes to
/// Replay's recaps is in exactly that state.
///
/// A badge showing how long you have been at your Mac is not a notification, so it should not
/// be waiting on notification permission. This draws the tile itself: the app's own icon, and
/// a capsule over it. Nothing to grant, nothing to refuse, and it looks the same everywhere.
@MainActor
final class DockTileView: NSView {
    var label: String? {
        didSet { if label != oldValue { needsDisplay = true } }
    }

    override func draw(_ dirtyRect: NSRect) {
        BundleIcon.image.draw(
            in: bounds, from: .zero, operation: .sourceOver, fraction: 1,
            respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high]
        )
        guard let label, !label.isEmpty else { return }

        // Sized from the tile rather than in points: the Dock draws this at whatever size it
        // is currently set to, and a badge measured in points is right at exactly one of them.
        let height = bounds.height * Design.Radius.dockBadgeHeight
        let font = NSFont.systemFont(
            ofSize: height * Design.Radius.dockBadgeTextRatio, weight: .semibold
        )
        let text = NSAttributedString(
            string: label,
            attributes: [.font: font, .foregroundColor: NSColor.white]
        )
        let padding = height * Design.Radius.dockBadgePaddingRatio
        let width = max(height, text.size().width + padding * 2)
        let inset = bounds.width * Design.Radius.dockBadgeInset
        let capsule = NSRect(
            x: bounds.maxX - width - inset,
            y: bounds.maxY - height - inset,
            width: width, height: height
        )

        // Red, as every Dock badge is: this is the one place in Replay where a colour is the
        // platform's convention rather than the app's own restraint.
        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: capsule, xRadius: height / 2, yRadius: height / 2).fill()
        NSColor.white.withAlphaComponent(Design.Colour.dockBadgeRim).setStroke()
        let rim = NSBezierPath(
            roundedRect: capsule.insetBy(dx: 0.5, dy: 0.5),
            xRadius: height / 2, yRadius: height / 2
        )
        rim.lineWidth = 1
        rim.stroke()

        text.draw(
            at: NSPoint(
                x: capsule.midX - text.size().width / 2,
                y: capsule.midY - text.size().height / 2
            )
        )
    }
}
