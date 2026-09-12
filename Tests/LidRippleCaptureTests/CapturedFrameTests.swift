import CoreVideo
import Metal
import Testing
@testable import LidRippleCapture

@Test func capturedFrameRetainsItsMetalBacking() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let cache = try CapturedFrame.makeTextureCache(device: device)
    let frame = try autoreleasepool { () throws -> CapturedFrame in
        let source = try makePixelBuffer(
            width: 32,
            height: 16,
            format: kCVPixelFormatType_32BGRA
        )
        CVPixelBufferLockBaseAddress(source, [])
        let baseAddress = try #require(CVPixelBufferGetBaseAddress(source))
        baseAddress.storeBytes(of: UInt32(0x0403_0201), as: UInt32.self)
        CVPixelBufferUnlockBaseAddress(source, [])
        return try CapturedFrame.make(pixelBuffer: source, textureCache: cache)
    }
    CVMetalTextureCacheFlush(cache, 0)

    #expect(frame.width == 32)
    #expect(frame.height == 16)
    #expect(frame.texture.width == 32)
    #expect(frame.texture.height == 16)
    #expect(frame.texture.pixelFormat == .bgra8Unorm)

    var copiedBytes = [UInt8](repeating: 0, count: 32 * 16 * 4)
    frame.texture.getBytes(
        &copiedBytes,
        bytesPerRow: 32 * 4,
        from: MTLRegionMake2D(0, 0, 32, 16),
        mipmapLevel: 0
    )
    #expect(Array(copiedBytes.prefix(4)) == [1, 2, 3, 4])
}

@Test func capturedFrameRejectsUnsupportedPixelFormats() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let cache = try CapturedFrame.makeTextureCache(device: device)
    let pixelBuffer = try makePixelBuffer(
        width: 8,
        height: 8,
        format: kCVPixelFormatType_OneComponent8
    )

    #expect(throws: CaptureError.unsupportedPixelFormat(kCVPixelFormatType_OneComponent8)) {
        try CapturedFrame.make(pixelBuffer: pixelBuffer, textureCache: cache)
    }
}

private func makePixelBuffer(
    width: Int,
    height: Int,
    format: OSType
) throws -> CVPixelBuffer {
    let attributes: [CFString: Any] = [
        kCVPixelBufferMetalCompatibilityKey: true,
        kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
    ]
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        format,
        attributes as CFDictionary,
        &pixelBuffer
    )
    #expect(status == kCVReturnSuccess)
    return try #require(pixelBuffer)
}
