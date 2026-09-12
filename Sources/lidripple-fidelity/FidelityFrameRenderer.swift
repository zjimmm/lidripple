import CoreVideo
import Foundation
import Metal
import LidRippleCapture
import LidRippleCore
import LidRippleRenderer

final class FidelityFrameRenderer {
    private let device: any MTLDevice
    private let commandQueue: any MTLCommandQueue
    private let renderer: FoldRenderer

    init(tuning: FoldTuning = .default) throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw FidelityError.metalUnavailable
        }
        self.device = device
        self.commandQueue = commandQueue
        renderer = try FoldRenderer(device: device, tuning: tuning)
    }

    func installSource(_ source: PixelFrame) throws {
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess,
              let cache else { throw FidelityError.metalUnavailable }
        let attributes: [CFString: Any] = [
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(
            nil,
            source.width,
            source.height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        ) == kCVReturnSuccess, let pixelBuffer else {
            throw FidelityError.metalUnavailable
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw FidelityError.metalUnavailable
        }
        let destinationStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        source.bytes.withUnsafeBytes { storage in
            guard let sourceAddress = storage.baseAddress else { return }
            for row in 0..<source.height {
                baseAddress.advanced(by: row * destinationStride).copyMemory(
                    from: sourceAddress.advanced(by: row * source.width * 4),
                    byteCount: source.width * 4
                )
            }
        }
        let captured = try CapturedFrame.make(pixelBuffer: pixelBuffer, textureCache: cache)
        try renderer.setSource(captured)
    }

    func render(progress: Double, width: Int, height: Int) throws -> PixelFrame {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget]
        guard let target = device.makeTexture(descriptor: descriptor),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw FidelityError.metalUnavailable
        }
        guard try renderer.render(progress: progress, to: target, commandBuffer: commandBuffer) else {
            throw FidelityError.renderProducedNoFrame
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw RendererError.commandBufferFailed(
                commandBuffer.error?.localizedDescription ?? "unknown Metal failure"
            )
        }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(
            &bytes,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        return try PixelFrame(width: width, height: height, bytes: bytes)
    }
}
