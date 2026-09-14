import AppKit
import CoreVideo
import Metal
import Testing
import LidRippleCapture
import LidRippleCore
import LidRippleRenderer
@testable import LidRippleOverlay

extension OverlayAppKitTests {
@Test func frostHandoffKeepsMeasuredGeometryAndClearsOnAbort() {
    guard let screen = NSScreen.main else { return }
    let presentation = FakePresentation()
    let presenter = OverlayPresenter(screen: screen, presentation: presentation)
    presenter.beginWakeCover()
    #expect(presenter.isWakeCoverActiveForTesting)
    #expect(presentation.view.isHidden)
    presenter.update(FoldState(phase: .unfolding, progress: 0.7, velocity: -1))
    #expect(presentation.states.last?.progress == 0.7)
    #expect(!presentation.view.isHidden)
    #expect(presenter.isWakeCoverActiveForTesting)
    presenter.abort()
    #expect(!presenter.isWakeCoverActiveForTesting)
    #expect(!presenter.windowForTesting.isVisible)
    #expect(OverlayPresenter.wakeCoverOpacity(elapsed: 0) == 1)
    #expect(abs(OverlayPresenter.wakeCoverOpacity(elapsed: 0.08) - 0.5) < 0.0001)
    #expect(OverlayPresenter.wakeCoverOpacity(elapsed: 0.16) == 0)
}

@Test func frostTimesOutWithoutAFrame() async throws {
    guard let screen = NSScreen.main else { return }
    let presenter = OverlayPresenter(screen: screen, presentation: FakePresentation())
    presenter.beginWakeCover()
    try await Task.sleep(for: .milliseconds(650))
    #expect(!presenter.isWakeCoverActiveForTesting)
    #expect(!presenter.windowForTesting.isVisible)
}

@Test func openingFramesReachRendererAtFullMeasuredDepthForBothEffects() {
    guard let screen = NSScreen.main else { return }
    let presentation = FakePresentation()
    let presenter = OverlayPresenter(screen: screen, presentation: presentation)
    for effect in DesktopEffect.allCases {
        presenter.setEffect(effect)
        for p in [0.8, 0.7, 0.6, 0.4, 0.2, 0.0] {
            presenter.update(FoldState(phase: .unfolding, progress: p, velocity: -1))
            #expect(presentation.states.last?.progress == p)
        }
        presenter.clearSource()
        presenter.update(FoldState(phase: .folding, progress: 0.8, velocity: 1))
        #expect(presentation.states.last?.progress == 0.8)
    }
}

@Test func presenterInitSucceedsOrFailsWithoutCrashing() {
    if let presenter = OverlayPresenter() {
        #expect(presenter.windowID != 0)
    }
}

@Test func presenterForwardsEveryStateToItsRenderingSurface() {
    guard let screen = NSScreen.main else { return }
    let presentation = FakePresentation()
    let presenter = OverlayPresenter(screen: screen, presentation: presentation)

    for phase in FoldPhase.allCases {
        presenter.update(FoldState(phase: phase, progress: 0.5, velocity: 0))
    }

    #expect(presentation.states.map(\.phase) == FoldPhase.allCases)
    #expect(presentation.states.allSatisfy { $0.progress == 0.5 })
}

@Test func presenterClearSourceForwardsToItsRenderingSurface() {
    guard let screen = NSScreen.main else { return }
    let presentation = FakePresentation()
    let presenter = OverlayPresenter(screen: screen, presentation: presentation)

    presenter.clearSource()

    #expect(presentation.clearCount == 1)
}

@Test func fallbackRevealClearsCapturedContentAndFollowsProgressAlpha() throws {
    guard let screen = NSScreen.main else { return }
    let presentation = FakePresentation()
    let presenter = OverlayPresenter(screen: screen, presentation: presentation)

    try presenter.setFallbackSource()
    presenter.update(FoldState(phase: .unfolding, progress: 0.65, velocity: -1))

    #expect(presentation.clearCount == 1)
    #expect(presentation.fallbackCount == 1)
    #expect(presenter.isFallbackRevealForTesting)
    #expect(abs(presenter.windowForTesting.alphaValue - 0.65) < 0.001)

    presenter.clearSource()
    #expect(!presenter.isFallbackRevealForTesting)
    #expect(presenter.windowForTesting.alphaValue == 1)
}

@Test func normalSourceResetsFallbackRevealAlpha() throws {
    guard let screen = NSScreen.main else { return }
    let presentation = FakePresentation()
    let presenter = OverlayPresenter(screen: screen, presentation: presentation)

    try presenter.setFallbackSource()
    presenter.update(FoldState(phase: .unfolding, progress: 0.3, velocity: -1))
    try presenter.setSource(.testFrame())

    #expect(!presenter.isFallbackRevealForTesting)
    #expect(presenter.windowForTesting.alphaValue == 1)
}

@Test func abortHidesAndDiscardsSource() {
    guard let screen = NSScreen.main else { return }
    let presentation = FakePresentation()
    let presenter = OverlayPresenter(screen: screen, presentation: presentation)
    presenter.update(FoldState(phase: .sealed, progress: 1, velocity: 0))

    presenter.abort()

    #expect(presentation.clearCount == 1)
    #expect(!presenter.windowForTesting.isVisible)
}

@Test func resizeRestoresWindowAndPresentationToTheTargetScreen() {
    guard let screen = NSScreen.main else { return }
    let presentation = FakePresentation()
    let presenter = OverlayPresenter(screen: screen, presentation: presentation)
    presenter.windowForTesting.setFrame(NSRect(x: 0, y: 0, width: 10, height: 10), display: false)
    presentation.view.frame = NSRect(x: 0, y: 0, width: 10, height: 10)

    presenter.resize(to: screen)

    #expect(presenter.windowForTesting.frame == screen.frame)
    #expect(presentation.view.frame == NSRect(origin: .zero, size: screen.frame.size))
}

@Test func reducedQualityForwardsToPresentation() {
    guard let screen = NSScreen.main else { return }
    let presentation = FakePresentation()
    let presenter = OverlayPresenter(screen: screen, presentation: presentation)

    presenter.setReducedQuality(true)

    #expect(presentation.reducedQualityValues == [true])
}
}

@MainActor
private final class FakePresentation: FoldPresentation {
    let view = NSView(frame: .zero)
    var states: [FoldState] = []
    var clearCount = 0
    var fallbackCount = 0
    var reducedQualityValues: [Bool] = []

    func setSource(_ frame: CapturedFrame) throws {}

    func useFallbackSource() throws {
        fallbackCount += 1
    }

    func clearSource() {
        clearCount += 1
    }

    func setReducedQuality(_ reduced: Bool) {
        reducedQualityValues.append(reduced)
    }

    func update(_ state: FoldState) {
        states.append(state)
    }
}

private extension CapturedFrame {
    static func testFrame() throws -> CapturedFrame {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RendererError.metalUnavailable
        }
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess,
              let cache else {
            throw RendererError.textureAllocationFailed
        }
        let attributes: [CFString: Any] = [
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(
            nil,
            1,
            1,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        ) == kCVReturnSuccess, let pixelBuffer else {
            throw RendererError.textureAllocationFailed
        }
        return try CapturedFrame.make(pixelBuffer: pixelBuffer, textureCache: cache)
    }
}

extension OverlayAppKitTests {
@Test func presenterUpdateDoesNotCrashAcrossEveryPhase() {
    guard let presenter = OverlayPresenter() else { return }

    for phase in FoldPhase.allCases {
        presenter.update(FoldState(phase: phase, progress: 0.5, velocity: 0))
    }
}
}
