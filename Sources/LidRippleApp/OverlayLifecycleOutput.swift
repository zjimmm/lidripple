import CoreGraphics
import LidRippleCapture
import LidRippleCore
import LidRippleIntegration
import LidRippleOverlay

/// Adapts the real one-window presenter to the integration target's AppKit-free
/// lifecycle protocol.
@MainActor
final class OverlayLifecycleOutput: FoldLifecycleOutput {
    let presenter: OverlayPresenter

    init(presenter: OverlayPresenter) {
        self.presenter = presenter
    }

    var captureExclusionWindowID: CGWindowID { presenter.windowID }

    func setSource(_ frame: CapturedFrame) throws { try presenter.setSource(frame) }
    func setFallbackSource() throws { try presenter.setFallbackSource() }
    func clearSource() { presenter.clearSource() }
    func update(_ state: FoldState) { presenter.update(state) }
    func hide() { presenter.hide() }
    func setReducedQuality(_ reduced: Bool) { presenter.setReducedQuality(reduced) }

    func reconfigureForBuiltInDisplay() -> Bool {
        presenter.reconfigureForBuiltInDisplay()
    }
}
