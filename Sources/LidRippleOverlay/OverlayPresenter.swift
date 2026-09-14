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
    private let container: NSView
    private let frost: NSVisualEffectView
    private var frostTimeout: Task<Void, Never>?
    private var frostStarted: TimeInterval?
    private var frostActive = false
    private var frostGeneration: UInt64 = 0

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
        let container = NSView(frame: presentation.view.frame)
        presentation.view.autoresizingMask = [.width, .height]
        container.addSubview(presentation.view)
        let frost = NSVisualEffectView(frame: container.bounds)
        frost.autoresizingMask = [.width, .height]
        frost.material = .hudWindow
        frost.blendingMode = .behindWindow
        frost.state = .active
        frost.isHidden = true
        container.addSubview(frost)
        window.contentView = container

        self.presentation = presentation
        self.window = window
        self.container = container
        self.frost = frost
    }

    /// Same excluded overlay window, no cached pixels. The native frosted
    /// material obscures the desktop while a fresh frame and pose are prepared.
    public func beginWakeCover() {
        endWakeCover()
        frostActive = true
        presentation.view.isHidden = true
        frost.alphaValue = 1
        frost.isHidden = false
        window.alphaValue = 1
        window.orderFrontRegardless()
        let generation = frostGeneration
        frostTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(550)) }
            catch { return }
            guard let self, self.frostGeneration == generation, self.frostActive else { return }
            let waitingForFrame = self.frostStarted == nil
            self.endWakeCover()
            if waitingForFrame { self.window.orderOut(nil) }
        }
    }

    private func endWakeCover() {
        frostGeneration &+= 1
        frostTimeout?.cancel()
        frostTimeout = nil
        frostActive = false
        frostStarted = nil
        frost.isHidden = true
        frost.alphaValue = 1
        presentation.view.isHidden = false
    }

    static func wakeCoverOpacity(elapsed: TimeInterval) -> Double {
        let t = min(max(elapsed / 0.16, 0), 1)
        return 1 - t * t * (3 - 2 * t)
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
        endWakeCover()
        presentation.clearSource()
        fallbackReveal = false
        window.alphaValue = 1
    }

    /// Temporarily removes the overlay without changing its installed source.
    public func hide() {
        endWakeCover()
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

    public func setEffect(_ effect: DesktopEffect) {
        presentation.setEffect(effect)
    }

    /// Installs generated pixels for the permission-free debug scrubber. This
    /// path never invokes ScreenCaptureKit and cannot contain desktop content.
    public func beginDebugPreview(tuning: FoldTuning) throws {
        guard let foldView = presentation as? FoldMetalView,
              let device = foldView.device
        else { throw RendererError.metalUnavailable }

        let source = try SyntheticFrame.makePreviewArtworkTexture(device: device)
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
        window.alphaValue = fallbackReveal
            ? CGFloat(min(max(state.progress, 0), 1))
            : 1

        switch state.phase {
        case .idle, .armed:
            if window.isVisible { window.orderOut(nil) }
        case .folding, .unfolding, .sealed:
            if !window.isVisible { window.orderFrontRegardless() }
        }
        presentation.update(state)
        if frostActive {
            if state.phase == .unfolding, !fallbackReveal {
                // Keep the first rendered pose behind frost. Its geometry is
                // unchanged; only the source-free cover fades away.
                presentation.view.isHidden = false
                let now = ProcessInfo.processInfo.systemUptime
                if frostStarted == nil { frostStarted = now }
                frost.alphaValue = Self.wakeCoverOpacity(elapsed: now - (frostStarted ?? now))
                if frost.alphaValue <= 0 { endWakeCover() }
            } else {
                endWakeCover()
            }
        }
    }

    var windowForTesting: OverlayWindow { window }
    var isFallbackRevealForTesting: Bool { fallbackReveal }
    var isWakeCoverActiveForTesting: Bool { frostActive }
}
