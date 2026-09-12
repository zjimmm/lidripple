import Testing
import LidRippleCore
@testable import LidRippleOverlay

@Test @MainActor func presenterInitSucceedsOrFailsWithoutCrashing() {
    if let presenter = OverlayPresenter() {
        #expect(presenter.windowID != 0)
    }
}

@Test @MainActor func presenterUpdateDoesNotCrashAcrossEveryPhase() {
    guard let presenter = OverlayPresenter() else { return }

    for phase in FoldPhase.allCases {
        presenter.update(FoldState(phase: phase, progress: 0.5, velocity: 0))
    }
}
