import AppKit

/// A folded screen above a quiet hinge line. Template rendering lets macOS
/// supply the correct tint for light/dark menu bars and selected menus.
@MainActor
public enum StatusBarIcon {
    public static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let screen = NSBezierPath()
            screen.lineWidth = 1.35
            screen.lineJoinStyle = .round
            screen.move(to: NSPoint(x: 4, y: 6))
            screen.line(to: NSPoint(x: 4, y: 14))
            screen.curve(to: NSPoint(x: 5.2, y: 15),
                controlPoint1: NSPoint(x: 4, y: 14.7),
                controlPoint2: NSPoint(x: 4.5, y: 15.15))
            screen.line(to: NSPoint(x: 13.2, y: 13.4))
            screen.curve(to: NSPoint(x: 14, y: 12.4),
                controlPoint1: NSPoint(x: 13.7, y: 13.3),
                controlPoint2: NSPoint(x: 14, y: 12.9))
            screen.line(to: NSPoint(x: 14, y: 4))
            screen.close()
            screen.stroke()

            let hinge = NSBezierPath()
            hinge.lineWidth = 1.35
            hinge.lineCapStyle = .round
            hinge.move(to: NSPoint(x: 2, y: 3))
            hinge.curve(to: NSPoint(x: 16, y: 3),
                controlPoint1: NSPoint(x: 6, y: 1.5),
                controlPoint2: NSPoint(x: 12, y: 1.5))
            hinge.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "LidRipple"
        return image
    }
}
