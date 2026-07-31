import AppKit

/// Draws the menu bar battery icon with a fill proportional to the actual
/// charge level, like the system battery item. Rendered as a template image
/// so it adapts to light/dark menu bars automatically.
enum BatteryIcon {
    static func make(percent: Int?, showBolt: Bool, critical: Bool = false) -> NSImage {
        let size = NSSize(width: 26, height: 13)
        // Colors resolve at draw time inside the handler, so labelColor picks
        // up the actual menu bar appearance even for the non-template
        // (red) variant.
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let strokeColor = critical ? NSColor.labelColor.withAlphaComponent(0.6)
                                       : NSColor.black.withAlphaComponent(0.6)
            let nubColor = critical ? NSColor.labelColor.withAlphaComponent(0.5)
                                    : NSColor.black.withAlphaComponent(0.5)
            let fillColor = critical ? NSColor.systemRed : NSColor.black

            // Battery body outline
            let body = NSRect(x: 0.5, y: 1.0, width: 21.5, height: 11.0)
            let outline = NSBezierPath(roundedRect: body, xRadius: 3.5, yRadius: 3.5)
            outline.lineWidth = 1
            strokeColor.setStroke()
            outline.stroke()

            // Terminal nub on the right
            nubColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 23.2, y: 4.6, width: 2.2, height: 3.8),
                         xRadius: 1.1, yRadius: 1.1).fill()

            // Proportional charge fill
            let level = max(0.0, min(1.0, Double(percent ?? 0) / 100.0))
            if level > 0 {
                let inner = body.insetBy(dx: 1.7, dy: 1.7)
                let fillWidth = max(2.0, inner.width * CGFloat(level))
                fillColor.setFill()
                NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY,
                                                 width: fillWidth, height: inner.height),
                             xRadius: 1.8, yRadius: 1.8).fill()
            }

            // Charging bolt. Erasing a slightly larger silhouette first gives
            // it clean contrast against the fill at high charge levels, then
            // filling the actual bolt on top keeps it visible even when the
            // fill is too small to reach the bolt at all (e.g. 10%) — an
            // erase alone is invisible wherever there's nothing to erase.
            if showBolt {
                let boltRect = NSRect(x: 7.0, y: 1.5, width: 8.5, height: 10.0)
                ctx.saveGState()
                ctx.setBlendMode(.destinationOut)
                boltPath(in: boltRect.insetBy(dx: -1, dy: -1)).fill()
                ctx.restoreGState()

                fillColor.setFill()
                boltPath(in: boltRect).fill()
            }
            return true
        }
        // The red variant must keep its color, so it can't be a template.
        image.isTemplate = !critical
        return image
    }

    private static func boltPath(in rect: NSRect) -> NSBezierPath {
        func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        let path = NSBezierPath()
        path.move(to: pt(0.62, 1.0))
        path.line(to: pt(0.0, 0.42))
        path.line(to: pt(0.40, 0.42))
        path.line(to: pt(0.35, 0.0))
        path.line(to: pt(1.0, 0.58))
        path.line(to: pt(0.57, 0.58))
        path.close()
        return path
    }
}
