import AppKit
import Foundation
import Testing
import LidRippleOverlay
@testable import LidRippleCapture

/// Opt-in only: the environment gate returns before ScreenCaptureKit content is
/// enumerated, so the ordinary suite can never trigger a TCC prompt.
@Test @MainActor func realBuiltInDisplayCapture() async throws {
    guard ProcessInfo.processInfo.environment["LIDRIPPLE_CAPTURE_SMOKE"] == "1" else {
        return
    }

    print(
        """
        lidripple capture smoke test: macOS may request Screen Recording permission.
        This test captures only the built-in display for under one second, retains one
        GPU-backed frame in memory, and writes nothing to disk or the network.
        """
    )

    let screen = try #require(BuiltInDisplay.screen())
    let displayID = try #require(BuiltInDisplay.displayID(for: screen))
    let presenter = try #require(OverlayPresenter())
    let coordinator = try CaptureCoordinator()

    do {
        let clock = ContinuousClock()
        let started = clock.now
        try await coordinator.warm(
            displayID: displayID,
            excludingWindowID: presenter.windowID
        )
        let warmCompleted = clock.now
        let frame = try await coordinator.freeze(waitingUpTo: 0.75)
        let frameReady = clock.now

        print(String(
            format: "CAPTURE_WARM_TIMING warm_start_ms=%.3f first_frame_after_warm_ms=%.3f total_ready_ms=%.3f configured_interval_ms=%.3f",
            smokeSeconds(started.duration(to: warmCompleted)) * 1_000,
            smokeSeconds(warmCompleted.duration(to: frameReady)) * 1_000,
            smokeSeconds(started.duration(to: frameReady)) * 1_000,
            1_000 / Double(CaptureConfiguration.warmFramesPerSecond)
        ))

        let expectedWidth = Int(
            (screen.frame.width * screen.backingScaleFactor).rounded()
        )
        let expectedHeight = Int(
            (screen.frame.height * screen.backingScaleFactor).rounded()
        )
        #expect(frame.width == expectedWidth)
        #expect(frame.height == expectedHeight)
        #expect(frame.texture.pixelFormat == .bgra8Unorm)

        await coordinator.reset()
        #expect(await coordinator.state == .idle)
    } catch {
        await coordinator.reset()
        throw error
    }
}

private func smokeSeconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
}
