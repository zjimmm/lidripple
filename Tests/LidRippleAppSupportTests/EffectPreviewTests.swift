import Testing
@testable import LidRippleAppSupport

@MainActor
struct EffectPreviewTests {
    @Test func loopPausesAtEndpointsAndReturnsSeamlessly() {
        #expect(EffectPreviewController.progress(elapsed: 0) == 0)
        #expect(EffectPreviewController.progress(elapsed: 0.7) == 0)
        #expect(abs(EffectPreviewController.progress(elapsed: 1.8) - 0.5) < 0.0001)
        #expect(EffectPreviewController.progress(elapsed: 3) == 1)
        #expect(abs(EffectPreviewController.progress(elapsed: 4.4) - 0.5) < 0.0001)
        #expect(EffectPreviewController.progress(elapsed: 5.9) == 0)
        #expect(EffectPreviewController.progress(elapsed: 6) == 0)
        #expect(EffectPreviewController.progress(elapsed: .nan) == 0)
        for step in 0...600 {
            #expect((0...1).contains(EffectPreviewController.progress(elapsed: Double(step) / 100)))
        }
    }
}
