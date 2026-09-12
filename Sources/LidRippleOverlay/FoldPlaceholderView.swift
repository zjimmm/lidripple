import AppKit

/// Temporary stand-in for Plan 2c's Metal renderer.
///
/// The view draws a flat black overlay whose opacity follows fold progress, which
/// is enough to verify the window and live sensor pipeline before capture and the
/// final fold shader exist.
public final class FoldPlaceholderView: NSView {
    public var progress: Double = 0 {
        didSet { needsDisplay = true }
    }

    public override var isOpaque: Bool { false }

    public override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let alpha = CGFloat(min(max(progress, 0), 1))
        NSColor.black.withAlphaComponent(alpha).setFill()
        bounds.fill()
    }
}
