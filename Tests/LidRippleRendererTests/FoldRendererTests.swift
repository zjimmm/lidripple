import Metal
import Testing
import LidRippleCore
@testable import LidRippleRenderer

@Test func rendererDoesNotEncodeWithoutASource() throws {
    let context = try RendererTestContext()
    let target = try context.makeTarget(width: 32, height: 16)
    let commandBuffer = try #require(context.commandQueue.makeCommandBuffer())

    #expect(try context.renderer.render(progress: 0.5, to: target, commandBuffer: commandBuffer) == false)
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    #expect(commandBuffer.status == .completed)
}

@Test func progressZeroIsAFullScreenSourceIdentity() throws {
    let context = try RendererTestContext()
    let sourceBytes = checkerboardGradient(width: 64, height: 40)
    let source = try context.makeTexture(width: 64, height: 40, bytes: sourceBytes)
    try context.renderer.setSource(texture: source)

    let rendered = try context.render(progress: 0, width: 64, height: 40)
    let maximumError = zip(rendered, sourceBytes)
        .map { abs(Int($0) - Int($1)) }
        .max() ?? 0
    #expect(maximumError <= 2)
}

@Test func laterProgressConsumesMorePixelsIntoTheVoid() throws {
    let context = try RendererTestContext()
    let source = try context.makeTexture(
        width: 96,
        height: 64,
        bytes: [UInt8](repeating: 220, count: 96 * 64 * 4)
    )
    try context.renderer.setSource(texture: source)

    let early = try context.render(progress: 0.25, width: 96, height: 64)
    let late = try context.render(progress: 0.75, width: 96, height: 64)

    #expect(warmBlackPixelCount(late) > warmBlackPixelCount(early))
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

private final class RendererTestContext {
    let device: any MTLDevice
    let commandQueue: any MTLCommandQueue
    let renderer: FoldRenderer

    init(tuning: FoldTuning = .default) throws {
        device = try #require(MTLCreateSystemDefaultDevice())
        commandQueue = try #require(device.makeCommandQueue())
        renderer = try FoldRenderer(device: device, tuning: tuning)
    }

    func makeTexture(width: Int, height: Int, bytes: [UInt8]) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead]
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: width * 4
        )
        return texture
    }

    func makeSolidTexture(
        width: Int,
        height: Int,
        bgra: [UInt8]
    ) throws -> any MTLTexture {
        try makeTexture(
            width: width,
            height: height,
            bytes: Array(repeating: bgra, count: width * height).flatMap { $0 }
        )
    }

    func makeTarget(width: Int, height: Int) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        return try #require(device.makeTexture(descriptor: descriptor))
    }

    func render(progress: Double, width: Int, height: Int) throws -> [UInt8] {
        let target = try makeTarget(width: width, height: height)
        let commandBuffer = try #require(commandQueue.makeCommandBuffer())
        #expect(try renderer.render(progress: progress, to: target, commandBuffer: commandBuffer))
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        #expect(commandBuffer.status == .completed)

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(
            &bytes,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        return bytes
    }
}

private func checkerboardGradient(width: Int, height: Int) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * width + x) * 4
            let checker = ((x / 8) + (y / 8)).isMultiple(of: 2) ? 36 : 0
            bytes[offset] = UInt8(min(255, x * 255 / max(width - 1, 1) + checker))
            bytes[offset + 1] = UInt8(min(255, y * 255 / max(height - 1, 1) + checker))
            bytes[offset + 2] = UInt8(min(255, (x + y) * 127 / max(width + height - 2, 1) + checker))
            bytes[offset + 3] = 255
        }
    }
    return bytes
}

private func warmBlackPixelCount(_ bytes: [UInt8]) -> Int {
    stride(from: 0, to: bytes.count, by: 4).reduce(into: 0) { count, offset in
        if bytes[offset] < 8, bytes[offset + 1] < 8, bytes[offset + 2] < 8 {
            count += 1
        }
    }
}
