import CoreGraphics
import Foundation
import Testing
import LidRippleCapture
import LidRippleCore
import LidRippleIntegration

@Test @MainActor func liveIntensityTuningIsPresentationOnly() async {
    let capture = TuningCapture()
    let output = TuningOutput()
    let coordinator = FoldLifecycleCoordinator(
        capture: capture,
        output: output,
        displayID: { 1 }
    )
    let originalState = coordinator.state
    let tuning = FoldTuning.default.withIntensity(0.5)

    coordinator.setTuning(tuning)

    #expect(output.tunings == [tuning])
    #expect(output.tunings[0].blurRadiusPx == FoldTuning.default.blurRadiusPx * 0.5)
    #expect(output.tunings[0].rotationDegrees == FoldTuning.default.rotationDegrees * 0.5)
    #expect(output.tunings[0].squashExponentGain
        == FoldTuning.default.squashExponentGain * 0.5)
    #expect(coordinator.state == originalState)
    #expect(await capture.operationCount == 0)
    #expect(output.updateCount == 0)
    #expect(output.hideCount == 0)
}

private actor TuningCapture: FoldCapturing {
    var operationCount = 0

    func warm(displayID: CGDirectDisplayID, excludingWindowID: CGWindowID) async throws {
        operationCount += 1
    }
    func freeze(waitingUpTo timeout: TimeInterval) async throws -> CapturedFrame {
        operationCount += 1
        throw TuningTestError.unexpectedCapture
    }
    func reset() async { operationCount += 1 }
}

@MainActor
private final class TuningOutput: FoldLifecycleOutput {
    var captureExclusionWindowID: CGWindowID { 9 }
    var tunings: [FoldTuning] = []
    var updateCount = 0
    var hideCount = 0

    func setSource(_ frame: CapturedFrame) throws {}
    func setFallbackSource() throws {}
    func clearSource() {}
    func update(_ state: FoldState) { updateCount += 1 }
    func hide() { hideCount += 1 }
    func setReducedQuality(_ reduced: Bool) {}
    func setTuning(_ tuning: FoldTuning) { tunings.append(tuning) }
    func reconfigureForBuiltInDisplay() -> Bool { true }
}

private enum TuningTestError: Error { case unexpectedCapture }
