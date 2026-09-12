import Metal
import Testing
@testable import LidRippleRenderer

@Test func pyramidHasAtMostSixCorrectlySizedLevels() throws {
    let context = try MetalTestContext()
    let source = try context.makeTexture(width: 64, height: 32, bytes: nil)
    let pyramid = try context.makePyramid(source: source)

    #expect(pyramid.levelCount == 6)
    #expect(pyramid.texture.mipmapLevelCount == 6)
    #expect(pyramid.generationPassCount == 5)
    for level in 0..<6 {
        #expect(pyramid.texture.width >> level == 64 >> level)
        #expect(max(pyramid.texture.height >> level, 1) == max(32 >> level, 1))
    }
}

@Test func tinyPyramidDoesNotInventUnavailableLevels() throws {
    let context = try MetalTestContext()
    let source = try context.makeTexture(width: 2, height: 1, bytes: nil)
    let pyramid = try context.makePyramid(source: source)

    #expect(pyramid.levelCount == 2)
    #expect(pyramid.generationPassCount == 1)
}

@Test func gaussianPyramidPreservesAConstantColor() throws {
    let context = try MetalTestContext()
    let pixel: [UInt8] = [31, 97, 211, 255]
    let source = try context.makeTexture(
        width: 32,
        height: 16,
        bytes: Array(repeating: pixel, count: 32 * 16).flatMap { $0 }
    )
    let pyramid = try context.makePyramid(source: source)

    for level in 0..<pyramid.levelCount {
        let bytes = try context.read(texture: pyramid.texture, level: level)
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            #expect(abs(Int(bytes[offset]) - 31) <= 1)
            #expect(abs(Int(bytes[offset + 1]) - 97) <= 1)
            #expect(abs(Int(bytes[offset + 2]) - 211) <= 1)
            #expect(bytes[offset + 3] == 255)
        }
    }
}

@Test func gaussianDownsampleKeepsACenteredImpulseSymmetric() throws {
    let context = try MetalTestContext()
    var bytes = [UInt8](repeating: 0, count: 9 * 9 * 4)
    for pixel in 0..<(9 * 9) { bytes[pixel * 4 + 3] = 255 }
    let center = (4 * 9 + 4) * 4
    bytes[center] = 255
    bytes[center + 1] = 255
    bytes[center + 2] = 255
    let source = try context.makeTexture(width: 9, height: 9, bytes: bytes)
    let pyramid = try context.makePyramid(source: source)
    let level = try context.read(texture: pyramid.texture, level: 1)
    let width = 4

    func blue(_ x: Int, _ y: Int) -> UInt8 { level[(y * width + x) * 4] }
    #expect(abs(Int(blue(1, 2)) - Int(blue(3, 2))) <= 1)
    #expect(abs(Int(blue(2, 1)) - Int(blue(2, 3))) <= 1)
    #expect(blue(2, 2) > blue(1, 1))
}

@Test func pyramidOwnsACopyOfLevelZero() throws {
    let context = try MetalTestContext()
    let original = [UInt8](repeating: 24, count: 8 * 8 * 4)
    let source = try context.makeTexture(width: 8, height: 8, bytes: original)
    let pyramid = try context.makePyramid(source: source)

    let replacement = [UInt8](repeating: 220, count: original.count)
    source.replace(
        region: MTLRegionMake2D(0, 0, 8, 8),
        mipmapLevel: 0,
        withBytes: replacement,
        bytesPerRow: 8 * 4
    )

    #expect(try context.read(texture: pyramid.texture, level: 0) == original)
}

@Test func pyramidRejectsNonBGRAInput() throws {
    let context = try MetalTestContext()
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm,
        width: 4,
        height: 4,
        mipmapped: false
    )
    let source = try #require(context.device.makeTexture(descriptor: descriptor))

    #expect(throws: RendererError.unsupportedSourcePixelFormat(.rgba8Unorm)) {
        try context.makePyramid(source: source)
    }
}

private struct MetalTestContext {
    let device: any MTLDevice
    let commandQueue: any MTLCommandQueue
    let pipelines: GaussianPipelines

    init() throws {
        device = try #require(MTLCreateSystemDefaultDevice())
        commandQueue = try #require(device.makeCommandQueue())
        let library = try FoldShaderLibrary.make(device: device)
        pipelines = try GaussianPipelines.make(device: device, library: library)
    }

    func makeTexture(width: Int, height: Int, bytes: [UInt8]?) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead]
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        if let bytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: bytes,
                bytesPerRow: width * 4
            )
        }
        return texture
    }

    func makePyramid(source: any MTLTexture) throws -> TexturePyramid {
        try TexturePyramid.make(
            source: source,
            device: device,
            commandQueue: commandQueue,
            pipelines: pipelines
        )
    }

    func read(texture: any MTLTexture, level: Int) throws -> [UInt8] {
        let width = max(texture.width >> level, 1)
        let height = max(texture.height >> level, 1)
        let bytesPerRow = width * 4
        let byteCount = bytesPerRow * height
        let buffer = try #require(device.makeBuffer(length: byteCount, options: .storageModeShared))
        let commandBuffer = try #require(commandQueue.makeCommandBuffer())
        let blit = try #require(commandBuffer.makeBlitCommandEncoder())
        blit.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: level,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: buffer,
            destinationOffset: 0,
            destinationBytesPerRow: bytesPerRow,
            destinationBytesPerImage: byteCount
        )
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        #expect(commandBuffer.status == .completed)

        return Array(
            UnsafeRawBufferPointer(start: buffer.contents(), count: byteCount)
        )
    }
}
