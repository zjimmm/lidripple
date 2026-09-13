import AppKit
import Metal
import QuartzCore
import Testing
import LidRippleCore
@testable import LidRippleRenderer

@Test @MainActor func metalViewUsesNativeVsyncedTripleBufferedConfiguration() throws {
    guard MTLCreateSystemDefaultDevice() != nil else { return }
    let view = try FoldMetalView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))

    #expect(view.colorPixelFormat == .bgra8Unorm)
    #expect(view.framebufferOnly)
    #expect(view.presentsWithTransaction == false)
    #expect(view.enableSetNeedsDisplay)
    #expect(view.isPaused)
    let layer = try #require(view.layer as? CAMetalLayer)
    #expect(layer.displaySyncEnabled)
    #expect(layer.maximumDrawableCount == 3)
}

@Test @MainActor func metalViewPausesWithoutAFrameAndWhileIdle() throws {
    guard let device = MTLCreateSystemDefaultDevice() else { return }
    let view = try FoldMetalView(frame: NSRect(x: 0, y: 0, width: 64, height: 40))

    view.update(FoldState(phase: .folding, progress: 0.4, velocity: 1))
    #expect(view.isPaused)
    #expect(view.progress == 0.4)

    let source = try SyntheticFrame.makeCheckerboardGradientTexture(
        device: device,
        width: 64,
        height: 40
    )
    try view.setPreviewSource(source)
    #expect(view.isPaused)

    view.update(.idle)
    #expect(view.isPaused)
    view.clearSource()
    #expect(view.isPaused)
}

@Test @MainActor func drawableSizeRoundsPointsAtBackingScale() {
    #expect(FoldMetalView.pixelSize(
        points: CGSize(width: 100.25, height: 50.25),
        backingScale: 2
    ) == CGSize(width: 201, height: 101))
    #expect(FoldMetalView.pixelSize(points: .zero, backingScale: 2) == CGSize(width: 1, height: 1))
}

@Test @MainActor func reducedQualityKeepsThePresentationAtSixtyFramesPerSecond() throws {
    guard MTLCreateSystemDefaultDevice() != nil else { return }
    let view = try FoldMetalView(frame: NSRect(x: 0, y: 0, width: 64, height: 40))

    view.setReducedQuality(true)

    #expect(view.preferredFramesPerSecond == 60)
}

@Test @MainActor func fallbackSourceCanDriveAnUnfoldWithoutCapturedContent() throws {
    guard MTLCreateSystemDefaultDevice() != nil else { return }
    let view = try FoldMetalView(frame: NSRect(x: 0, y: 0, width: 64, height: 40))

    try view.useFallbackSource()
    view.update(FoldState(phase: .unfolding, progress: 0.5, velocity: -1))

    #expect(view.isPaused)
}

@Test @MainActor func sealedFrameDrawsOnceThenPauses() throws {
    guard MTLCreateSystemDefaultDevice() != nil else { return }
    let view = try FoldMetalView(frame: NSRect(x: 0, y: 0, width: 64, height: 40))
    try view.useFallbackSource()

    view.update(FoldState(phase: .sealed, progress: 1, velocity: 0))

    #expect(view.isPaused)
}
