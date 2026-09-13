import Metal
import Testing
import LidRippleCore
@testable import LidRippleRenderer

@Test func foldUniformsHaveAnExplicitMetalCompatibleLayout() {
    #expect(MemoryLayout<FoldUniforms>.size == 112)
    #expect(MemoryLayout<FoldUniforms>.stride == 112)
    #expect(MemoryLayout<FoldUniforms>.alignment == 16)
}

@Test func foldUniformsCarryReducedQualityWithoutChangingOtherInputs() {
    let normal = FoldUniforms.make(
        progress: 0.5,
        tuning: .default,
        viewportSize: SIMD2<Int>(320, 200),
        sourceSize: SIMD2<Int>(640, 400)
    )
    let reduced = FoldUniforms.make(
        progress: 0.5,
        tuning: .default,
        viewportSize: SIMD2<Int>(320, 200),
        sourceSize: SIMD2<Int>(640, 400),
        reducedQuality: true
    )

    #expect(normal.quality.x == 0)
    #expect(reduced.quality.x == 1)
    #expect(normal.geometry == reduced.geometry)
    #expect(normal.cameraAndBlur == reduced.cameraAndBlur)
}

@Test func foldUniformsClampProgressAndInvalidDimensions() {
    let tuning = FoldTuning.default
    let low = FoldUniforms.make(
        progress: -1,
        tuning: tuning,
        viewportSize: SIMD2<Int>(0, -4),
        sourceSize: SIMD2<Int>(-1, 0)
    )
    let high = FoldUniforms.make(
        progress: 9,
        tuning: tuning,
        viewportSize: SIMD2<Int>(320, 200),
        sourceSize: SIMD2<Int>(640, 400)
    )

    #expect(low.geometry.x == 0)
    #expect(low.dimensions == SIMD4<Float>(1, 1, 1, 1))
    #expect(high.geometry.x == Float(tuning.maxProgress))
    #expect(high.dimensions == SIMD4<Float>(320, 200, 640, 400))
}

@Test func foldUniformsCarryEveryVisualTuningGroup() {
    let tuning = FoldTuning.default
    let uniforms = FoldUniforms.make(
        progress: 0.5,
        tuning: tuning,
        viewportSize: SIMD2<Int>(320, 200),
        sourceSize: SIMD2<Int>(640, 400)
    )

    #expect(uniforms.geometry.y == Float(tuning.squashExponentGain))
    #expect(uniforms.quality.y == Float(tuning.geometryProgressExponent))
    #expect(uniforms.quality.z == Float(tuning.sealFadeStart))
    #expect(uniforms.cameraAndBlur.z == Float(tuning.blurRadiusPx))
    #expect(uniforms.voidAndRim.x == Float(tuning.voidSpeed))
    #expect(uniforms.finish.y == Float(tuning.coolTintStrength))
    #expect(SIMD3<Float>(
        uniforms.colorAndTap.x,
        uniforms.colorAndTap.y,
        uniforms.colorAndTap.z
    ) == SIMD3<Float>(
        Float(tuning.warmBlackRed),
        Float(tuning.warmBlackGreen),
        Float(tuning.warmBlackBlue)
    ))
    #expect(uniforms.colorAndTap.w == Float(tuning.blurExtraTapDistance))
}

@Test func systemMetalCompilerBuildsEveryShaderEntryPoint() throws {
    guard let device = MTLCreateSystemDefaultDevice() else { return }
    let library = try FoldShaderLibrary.make(device: device)

    #expect(library.makeFunction(name: "backdropVertex") != nil)
    #expect(library.makeFunction(name: "backdropFragment") != nil)
    #expect(library.makeFunction(name: "foldVertex") != nil)
    #expect(library.makeFunction(name: "foldFragment") != nil)
    #expect(library.makeFunction(name: "gaussianHorizontal") != nil)
    #expect(library.makeFunction(name: "gaussianVertical") != nil)
}
