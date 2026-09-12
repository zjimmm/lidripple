import Testing
import LidRippleCore
@testable import LidRippleOverlay

@Test @MainActor func presenterInitSucceedsOrFailsWithoutCrashing() {
    _ = OverlayPresenter()
}

@Test @MainActor func presenterUpdateDoesNotCrashAcrossEveryPhase() {
    guard let presenter = OverlayPresenter() else { return }

    for phase in FoldPhase.allCases {
        presenter.update(FoldState(phase: phase, progress: 0.5, velocity: 0))
    }
}
