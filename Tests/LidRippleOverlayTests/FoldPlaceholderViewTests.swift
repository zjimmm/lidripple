import AppKit
import Testing
@testable import LidRippleOverlay

@Test @MainActor func settingProgressMarksTheViewForRedraw() {
    let view = FoldPlaceholderView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    let window = NSWindow(
        contentRect: view.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = view
    view.needsDisplay = false
    view.progress = 0.5
    #expect(view.needsDisplay)
}

@Test @MainActor func placeholderViewIsNeverOpaque() {
    let view = FoldPlaceholderView(frame: .zero)
    #expect(!view.isOpaque)
}

@Test @MainActor func progressDefaultsToZero() {
    let view = FoldPlaceholderView(frame: .zero)
    #expect(view.progress == 0)
}
