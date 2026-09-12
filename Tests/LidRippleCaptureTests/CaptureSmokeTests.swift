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
        try await coordinator.warm(
            displayID: displayID,
            excludingWindowID: presenter.windowID
        )
        try await Task.sleep(for: .milliseconds(750))
        let frame = try await coordinator.freeze()

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
