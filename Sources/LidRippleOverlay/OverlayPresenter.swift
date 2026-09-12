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
    private var fallbackReveal = false
    private var debugPreview = false

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
        fallbackReveal = false
        window.alphaValue = 1
    }

    /// Installs a generated warm-black source after first discarding any
    /// captured pixels. During unfolding, window alpha follows fold progress so
    /// capture failure reveals the desktop without ever replaying stale content.
    public func setFallbackSource() throws {
        presentation.clearSource()
        do {
            try presentation.useFallbackSource()
            fallbackReveal = true
        } catch {
            fallbackReveal = false
            window.alphaValue = 1
            window.orderOut(nil)
            throw error
        }
    }

    public func clearSource() {
        presentation.clearSource()
        fallbackReveal = false
        window.alphaValue = 1
    }

    /// Temporarily removes the overlay without changing its installed source.
    public func hide() {
        window.orderOut(nil)
    }

    /// Immediately hides the overlay and discards all source content.
    public func abort() {
        clearSource()
        window.orderOut(nil)
    }

    /// Moves and resizes the overlay and drawable to the supplied display.
    public func resize(to screen: NSScreen) {
        window.setFrame(screen.frame, display: true)
        presentation.view.frame = NSRect(origin: .zero, size: screen.frame.size)
    }

    /// Re-resolves the built-in panel after a display configuration change.
    @discardableResult
    public func reconfigureForBuiltInDisplay() -> Bool {
        guard let screen = BuiltInDisplay.screen() else {
            abort()
            return false
        }
        resize(to: screen)
        return true
    }

    /// Low-power and thermal-pressure mode changes blur taps, never cadence.
    public func setReducedQuality(_ reduced: Bool) {
        presentation.setReducedQuality(reduced)
    }

    /// Applies presentation-only tuning without changing capture or visibility.
    public func setTuning(_ tuning: FoldTuning) {
        presentation.setTuning(tuning)
    }

    /// Installs generated pixels for the permission-free debug scrubber. This
    /// path never invokes ScreenCaptureKit and cannot contain desktop content.
    public func beginDebugPreview(tuning: FoldTuning) throws {
        guard let foldView = presentation as? FoldMetalView,
              let device = foldView.device
        else { throw RendererError.metalUnavailable }

        let scale = window.screen?.backingScaleFactor ?? 1
        let size = presentation.view.bounds.size
        let width = max(Int((size.width * scale).rounded()), 1)
        let height = max(Int((size.height * scale).rounded()), 1)
        let source = try SyntheticFrame.makeCheckerboardGradientTexture(
            device: device,
            width: width,
            height: height
        )
        foldView.updateTuning(tuning)
        try foldView.setPreviewSource(source)
        fallbackReveal = false
        debugPreview = true
        updateDebugPreview(progress: 0, direction: 1)
    }

    public func updateDebugPreview(progress: Double, direction: Double) {
        guard debugPreview else { return }
        let clamped = min(max(progress, 0), FoldTuning.default.maxProgress)
        let phase: FoldPhase
        if clamped >= 1 {
            phase = .sealed
        } else {
            phase = direction < 0 ? .unfolding : .folding
        }
        presentation.update(FoldState(phase: phase, progress: clamped, velocity: direction))
        window.alphaValue = 1
        window.orderFrontRegardless()
    }

    public func endDebugPreview() {
        guard debugPreview else { return }
        debugPreview = false
        clearSource()
        window.orderOut(nil)
    }

    public func update(_ state: FoldState) {
        presentation.update(state)
        window.alphaValue = fallbackReveal
            ? CGFloat(min(max(state.progress, 0), 1))
            : 1

        switch state.phase {
        case .idle, .armed:
            window.orderOut(nil)
        case .folding, .unfolding, .sealed:
            window.orderFrontRegardless()
        }
    }

    var windowForTesting: OverlayWindow { window }
    var isFallbackRevealForTesting: Bool { fallbackReveal }
}
