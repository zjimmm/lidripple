import AppKit
import LidRippleCore

/// Owns the fold overlay and maps driver phases to its visible lifecycle.
///
/// Nothing is shown while the driver is idle or merely armed. Folding,
/// unfolding, and sealed states keep the window above the desktop so the final
/// folded frame can remain in place until teardown.
@MainActor
public final class OverlayPresenter {
    private let window: OverlayWindow
    private let placeholderView: FoldPlaceholderView

    public init?() {
        guard let screen = BuiltInDisplay.screen() else { return nil }

        let view = FoldPlaceholderView(
            frame: NSRect(origin: .zero, size: screen.frame.size)
        )
        let window = OverlayWindow(screen: screen)
        window.contentView = view

        self.placeholderView = view
        self.window = window
    }

    public func update(_ state: FoldState) {
        placeholderView.progress = state.progress

        switch state.phase {
        case .idle, .armed:
            window.orderOut(nil)
        case .folding, .unfolding, .sealed:
            window.orderFrontRegardless()
        }
    }
}
