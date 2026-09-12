import Metal
import Testing
import LidRippleCore
@testable import LidRippleRenderer

final class RendererTestContext {
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
