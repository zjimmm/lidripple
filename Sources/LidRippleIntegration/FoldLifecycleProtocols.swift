import CoreGraphics
import Foundation
import LidRippleCapture
import LidRippleCore

/// The capture operations needed by the app lifecycle. Keeping this seam small
/// makes the sleep/lock/re-entrancy rules testable without Screen Recording
/// permission or a WindowServer capture stream.
public protocol FoldCapturing: Sendable {
    func warm(
        displayID: CGDirectDisplayID,
        excludingWindowID: CGWindowID
    ) async throws
    func freeze(waitingUpTo timeout: TimeInterval) async throws -> CapturedFrame
    func reset() async
}

extension CaptureCoordinator: FoldCapturing {}

/// UI operations driven by `FoldLifecycleCoordinator`. The production
/// conformance lives in LidRippleOverlay; tests use an in-memory recorder.
@MainActor
public protocol FoldLifecycleOutput: AnyObject {
    var captureExclusionWindowID: CGWindowID { get }

    func setSource(_ frame: CapturedFrame) throws
    func setFallbackSource() throws
    func clearSource()
    func update(_ state: FoldState)
    func hide()
    func setReducedQuality(_ reduced: Bool)
    /// Applies final fidelity tuning plus the user's FR-17 intensity scaling.
    /// This is presentation-only and must not start capture or reveal a window.
    func setTuning(_ tuning: FoldTuning)

    /// Moves the one owned overlay to the current built-in display. Returns
    /// false when no built-in display is currently available.
    func reconfigureForBuiltInDisplay() -> Bool
}

public extension FoldLifecycleOutput {
    /// Compatibility default for non-rendering diagnostic/test outputs.
    func setTuning(_ tuning: FoldTuning) {}
}

public enum FoldLifecycleAvailability: Equatable, Sendable {
    case active
    case locked
    case sessionInactive
    case displayUnavailable
    case inputUnavailable
    case disabled
}
