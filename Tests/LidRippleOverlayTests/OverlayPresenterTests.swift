import AppKit
import Testing
import LidRippleCapture
import LidRippleCore
import LidRippleRenderer
@testable import LidRippleOverlay

@Test @MainActor func presenterInitSucceedsOrFailsWithoutCrashing() {
    if let presenter = OverlayPresenter() {
        #expect(presenter.windowID != 0)
    }
}

@Test @MainActor func presenterForwardsEveryStateToItsRenderingSurface() {
    guard let screen = NSScreen.main else { return }
    let presentation = FakePresentation()
    let presenter = OverlayPresenter(screen: screen, presentation: presentation)

    for phase in FoldPhase.allCases {
        presenter.update(FoldState(phase: phase, progress: 0.5, velocity: 0))
    }

    #expect(presentation.states.map(\.phase) == FoldPhase.allCases)
    #expect(presentation.states.allSatisfy { $0.progress == 0.5 })
}

@Test @MainActor func presenterClearSourceForwardsToItsRenderingSurface() {
    guard let screen = NSScreen.main else { return }
    let presentation = FakePresentation()
    let presenter = OverlayPresenter(screen: screen, presentation: presentation)

    presenter.clearSource()

    #expect(presentation.clearCount == 1)
}

@MainActor
private final class FakePresentation: FoldPresentation {
    let view = NSView(frame: .zero)
    var states: [FoldState] = []
    var clearCount = 0

    func setSource(_ frame: CapturedFrame) throws {}

    func clearSource() {
        clearCount += 1
    }

    func update(_ state: FoldState) {
        states.append(state)
    }
}

@Test @MainActor func presenterUpdateDoesNotCrashAcrossEveryPhase() {
    guard let presenter = OverlayPresenter() else { return }

    for phase in FoldPhase.allCases {
        presenter.update(FoldState(phase: phase, progress: 0.5, velocity: 0))
    }
}
