import AppKit
import CoreGraphics
import LidRippleCapture
import LidRippleCore
import LidRippleRenderer

/// Owns the fold overlay and maps driver phases to its visible lifecycle.
///
/// Nothing is shown while the driver is idle or merely armed. Folding,
/// unfolding, and sealed states keep the window above the desktop so the final
/// folded frame can remain in place until teardown.
@MainActor
public final class OverlayPresenter {
    private let window: OverlayWindow
    private let presentation: any FoldPresentation

    /// WindowServer identifier used to exclude the overlay from screen capture.
    public var windowID: CGWindowID { CGWindowID(window.windowNumber) }

    public convenience init?() {
        guard let screen = BuiltInDisplay.screen() else { return nil }

        guard let presentation = try? FoldMetalView(
            frame: NSRect(origin: .zero, size: screen.frame.size)
        ) else { return nil }
        self.init(screen: screen, presentation: presentation)
    }

    init(screen: NSScreen, presentation: any FoldPresentation) {
        let window = OverlayWindow(screen: screen)
        presentation.view.frame = NSRect(origin: .zero, size: screen.frame.size)
        window.contentView = presentation.view

        self.presentation = presentation
        self.window = window
    }

    public func setSource(_ frame: CapturedFrame) throws {
        try presentation.setSource(frame)
    }

    public func clearSource() {
        presentation.clearSource()
    }

    public func update(_ state: FoldState) {
        presentation.update(state)

        switch state.phase {
        case .idle, .armed:
            window.orderOut(nil)
        case .folding, .unfolding, .sealed:
            window.orderFrontRegardless()
        }
    }
}
