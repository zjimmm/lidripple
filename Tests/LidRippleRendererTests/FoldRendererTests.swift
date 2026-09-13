import Metal
import Testing
import LidRippleCore
@testable import LidRippleRenderer

@Test func rendererDoesNotEncodeWithoutASource() throws {
    let context = try RendererTestContext()
    #expect(context.renderer.pyramidBuildCount == 0)
    let target = try context.makeTarget(width: 32, height: 16)
    let commandBuffer = try #require(context.commandQueue.makeCommandBuffer())

    #expect(try context.renderer.render(progress: 0.5, to: target, commandBuffer: commandBuffer) == false)
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    #expect(commandBuffer.status == .completed)
}

@Test func progressZeroIsAFullScreenSourceIdentity() throws {
    let context = try RendererTestContext()
    let sourceBytes = SyntheticFrame.checkerboardGradientBytes(width: 64, height: 40)
    let source = try context.makeTexture(width: 64, height: 40, bytes: sourceBytes)
    try context.renderer.setSource(texture: source)

    let rendered = try context.render(progress: 0, width: 64, height: 40)
    let maximumError = zip(rendered, sourceBytes)
        .map { abs(Int($0) - Int($1)) }
        .max() ?? 0
    #expect(maximumError <= 2)
}

@Test func midClosePreservesSceneColorAndOnlyFinalSealTurnsNearBlack() throws {
    let context = try RendererTestContext()
    let source = try context.makeTexture(
        width: 96,
        height: 64,
        bytes: [UInt8](repeating: 220, count: 96 * 64 * 4)
    )
    try context.renderer.setSource(texture: source)

    let middle = try context.render(progress: 0.5, width: 96, height: 64)
    let late = try context.render(progress: 0.75, width: 96, height: 64)
    let sealed = try context.render(progress: 1, width: 96, height: 64)

    let pixelCount = 96 * 64
    #expect(warmBlackPixelCount(middle) < pixelCount / 20)
    #expect(warmBlackPixelCount(late) < pixelCount / 20)
    #expect(warmBlackPixelCount(sealed) > pixelCount * 9 / 10)

    // The source-derived backing, rather than warm-black clear color, fills
    // the exposed top of the screen while the panel folds toward the hinge.
    let topCenter = (2 * 96 + 48) * 4
    #expect(late[topCenter] > 170)
    #expect(late[topCenter + 1] > 170)
    #expect(late[topCenter + 2] > 170)
}

@Test func exposedBackingDoesNotRepeatLargeSourceWindows() throws {
    let width = 96
    let height = 64
    let context = try RendererTestContext()
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * width + x) * 4
            let color: [UInt8] = x < width / 2
                ? [30, 60, 210, 255] : [230, 235, 245, 255]
            bytes[offset..<(offset + 4)] = color[0..<4]
        }
    }
    try context.renderer.setSource(texture: context.makeTexture(
        width: width, height: height, bytes: bytes
    ))

    let frame = try context.render(progress: 0.75, width: width, height: height)
    let exposedRow = 2
    let backingPixels = [8, 48, 88].map { x in
        let offset = (exposedRow * width + x) * 4
        return Array(frame[offset..<(offset + 4)])
    }
    #expect(backingPixels[0] == backingPixels[1])
    #expect(backingPixels[1] == backingPixels[2])
    #expect(backingPixels[0][0] > 80)
    #expect(backingPixels[0][2] > 80)
}

@Test func hingeShadowIsLocalInsteadOfClimbingAcrossThePanel() throws {
    var tuning = FoldTuning.default
    tuning.rotationDegrees = 0
    tuning.squashExponentGain = 0
    tuning.blurRadiusPx = 0
    tuning.rimIntensity = 0
    tuning.coolTintStrength = 0
    tuning.vignetteStrength = 0
    tuning.ditherAmplitude = 0
    let context = try RendererTestContext(tuning: tuning)
    let source = try context.makeSolidTexture(width: 64, height: 40, bgra: [220, 220, 220, 255])
    try context.renderer.setSource(texture: source)

    let rendered = try context.render(progress: 0.75, width: 64, height: 40)
    let top = (2 * 64 + 32) * 4
    let middle = (20 * 64 + 32) * 4
    let hinge = (39 * 64 + 32) * 4
    #expect(rendered[top] > 200)
    #expect(rendered[middle] > 200)
    #expect(rendered[hinge] < 120)
}

@Test func replacingSourceBuildsOnceAndChangesTheNextFrame() throws {
    let context = try RendererTestContext()
    let red = try context.makeSolidTexture(width: 32, height: 20, bgra: [0, 0, 255, 255])
    let blue = try context.makeSolidTexture(width: 32, height: 20, bgra: [255, 0, 0, 255])

    try context.renderer.setSource(texture: red)
    let first = try context.render(progress: 0, width: 32, height: 20)
    _ = try context.render(progress: 0.5, width: 32, height: 20)
    #expect(context.renderer.pyramidBuildCount == 1)

    try context.renderer.setSource(texture: blue)
    let second = try context.render(progress: 0, width: 32, height: 20)
    #expect(context.renderer.pyramidBuildCount == 2)
    #expect(first[0..<4] == [0, 0, 255, 255])
    #expect(second[0..<4] == [255, 0, 0, 255])
}

@Test func bottomHingeRowStaysFixedWhileTheRestOfTheMeshFolds() throws {
    var tuning = FoldTuning.default
    tuning.blurRadiusPx = 0
    tuning.voidSpeed = -10
    tuning.rimIntensity = 0
    tuning.coolTintStrength = 0
    tuning.vignetteStrength = 0
    tuning.ditherAmplitude = 0
    let context = try RendererTestContext(tuning: tuning)
    let source = try context.makeSolidTexture(width: 64, height: 40, bgra: [220, 220, 220, 255])
    try context.renderer.setSource(texture: source)

    let rendered = try context.render(progress: 0.8, width: 64, height: 40)
    let bottomCenter = ((40 - 1) * 64 + 32) * 4
    #expect(rendered[bottomCenter] > 200)
    #expect(rendered[bottomCenter + 1] > 200)
    #expect(rendered[bottomCenter + 2] > 200)
    #expect(rendered[bottomCenter + 3] == 255)
}

@Test func clearSourceStopsFurtherEncoding() throws {
    let context = try RendererTestContext()
    let source = try context.makeSolidTexture(width: 8, height: 8, bgra: [10, 20, 30, 255])
    try context.renderer.setSource(texture: source)
    context.renderer.clearSource()
    let target = try context.makeTarget(width: 8, height: 8)
    let commandBuffer = try #require(context.commandQueue.makeCommandBuffer())

    #expect(try context.renderer.render(progress: 0.5, to: target, commandBuffer: commandBuffer) == false)
}

@Test func tuningHotReloadDoesNotRebuildTheSourcePyramid() throws {
    let context = try RendererTestContext()
    let source = try context.makeSolidTexture(width: 32, height: 20, bgra: [180, 180, 180, 255])
    try context.renderer.setSource(texture: source)
    let before = try context.render(progress: 0.5, width: 32, height: 20)

    var tuning = FoldTuning.default
    tuning.voidSpeed = 0.4
    tuning.rimIntensity = 0
    context.renderer.updateTuning(tuning)
    let after = try context.render(progress: 0.5, width: 32, height: 20)

    #expect(before != after)
    #expect(context.renderer.tuning == tuning)
    #expect(context.renderer.pyramidBuildCount == 1)
}

@Test func reducedQualityChangesFragmentTapCountWithoutRebuildingSource() throws {
    let context = try RendererTestContext()
    let source = try context.makeSolidTexture(width: 32, height: 20, bgra: [180, 180, 180, 255])
    try context.renderer.setSource(texture: source)

    #expect(context.renderer.fragmentBlurTapCount == 3)
    context.renderer.setReducedQuality(true)
    #expect(context.renderer.isReducedQuality)
    #expect(context.renderer.fragmentBlurTapCount == 1)
    #expect(context.renderer.pyramidBuildCount == 1)

    context.renderer.setReducedQuality(false)
    #expect(context.renderer.fragmentBlurTapCount == 3)
    #expect(context.renderer.pyramidBuildCount == 1)
}

@Test func fallbackSourceReplacesPreviouslyCapturedPixelsWithWarmBlack() throws {
    var tuning = FoldTuning.default
    tuning.rotationDegrees = 0
    tuning.squashExponentGain = 0
    tuning.blurRadiusPx = 0
    tuning.voidSpeed = 0
    tuning.rimIntensity = 0
    tuning.coolTintStrength = 0
    tuning.vignetteStrength = 0
    tuning.ditherAmplitude = 0
    let context = try RendererTestContext(tuning: tuning)
    let captured = try context.makeSolidTexture(width: 8, height: 8, bgra: [0, 0, 255, 255])
    try context.renderer.setSource(texture: captured)

    try context.renderer.useFallbackSource()
    let rendered = try context.render(progress: 0, width: 8, height: 8)
    let expected = [
        UInt8((tuning.warmBlackBlue * 255).rounded()),
        UInt8((tuning.warmBlackGreen * 255).rounded()),
        UInt8((tuning.warmBlackRed * 255).rounded()),
        UInt8.max,
    ]

    #expect(Array(rendered[0..<4]) == expected)
    #expect(stride(from: 0, to: rendered.count, by: 4).allSatisfy { offset in
        Array(rendered[offset..<(offset + 4)]) == expected
    })
    #expect(context.renderer.pyramidBuildCount == 2)
}

private func warmBlackPixelCount(_ bytes: [UInt8]) -> Int {
    stride(from: 0, to: bytes.count, by: 4).reduce(into: 0) { count, offset in
        if bytes[offset] < 8, bytes[offset + 1] < 8, bytes[offset + 2] < 8 {
            count += 1
        }
    }
}
