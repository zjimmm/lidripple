import Testing
import LidRippleCore
@testable import LidRippleRenderer

@Test func measuredOpeningProducesDistinctRenderedFramesForBothEffects() throws {
    let context = try RendererTestContext()
    try context.renderer.setSource(texture: context.makeTexture(width: 128, height: 80,
        bytes: SyntheticFrame.checkerboardGradientBytes(width: 128, height: 80)))
    for effect in DesktopEffect.allCases {
        context.renderer.setEffect(effect)
        let driver = FoldDriver()
        driver.beginScriptedUnfold(now: 10)
        driver.alignScriptedOpening(.init(degrees: 35, timestamp: 10))
        var frames = Set<[UInt8]>()
        for frame in 1...120 {
            let time = 10 + Double(frame) / 60
            driver.trackScriptedOpening(.init(degrees: (35 + Double(frame) / 2).rounded(), timestamp: time))
            let state = driver.tick(now: time)
            frames.insert(try context.render(progress: state.progress, width: 128, height: 80))
        }
        #expect(frames.count > 100, "\(effect) opening must not collapse into a few repeated frames")
    }
}

@Test func ripplePreservesOpenDesktopAndSealsAtClose() throws {
    let context = try RendererTestContext()
    context.renderer.setEffect(.ripple)
    let bytes = SyntheticFrame.checkerboardGradientBytes(width: 96, height: 64)
    try context.renderer.setSource(texture: context.makeTexture(width: 96, height: 64, bytes: bytes))
    let open = try context.render(progress: 0, width: 96, height: 64)
    #expect(zip(open, bytes).allSatisfy { abs(Int($0) - Int($1)) <= 2 })
    let middle = try context.render(progress: 0.5, width: 96, height: 64)
    #expect(zip(middle, open).filter { abs(Int($0) - Int($1)) > 8 }.count > 100)
    #expect(stride(from: 3, to: middle.count, by: 4).allSatisfy { middle[$0] == 255 })
    // No wall-clock drift or direction-reset discontinuity at the same angle.
    #expect(try context.render(progress: 0.5, width: 96, height: 64) == middle)
    let sealed = try context.render(progress: 1, width: 96, height: 64)
    #expect(stride(from: 0, to: sealed.count, by: 4).allSatisfy {
        sealed[$0] < 8 && sealed[$0 + 1] < 8 && sealed[$0 + 2] < 8
    })
    context.renderer.setEffect(.fold)
    #expect(try context.render(progress: 0.5, width: 96, height: 64) != middle)
    context.renderer.setEffect(.ripple)
    #expect(try context.render(progress: 0.5, width: 96, height: 64) == middle)
    #expect(context.renderer.pyramidBuildCount == 1)
}
