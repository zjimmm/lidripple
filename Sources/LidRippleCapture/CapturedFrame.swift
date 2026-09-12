import CoreVideo
import Metal

/// One immutable screen frame whose IOSurface-backed Metal texture remains valid
/// after capture stops.
///
/// `MTLTexture` objects are designed to be encoded from Metal work queues. All state
/// exposed here is immutable, and the CoreVideo wrapper is retained solely for
/// lifetime, so crossing an actor boundary is safe.
public final class CapturedFrame: @unchecked Sendable {
    public let texture: any MTLTexture
    public let width: Int
    public let height: Int

    // CoreVideo owns the IOSurface relationship. Keep the wrapper alive for at least
    // as long as the Metal texture rather than relying on undocumented transitive
    // retention after a capture callback returns.
    private let backingTexture: CVMetalTexture

    private init(texture: any MTLTexture, backingTexture: CVMetalTexture) {
        self.texture = texture
        self.width = texture.width
        self.height = texture.height
        self.backingTexture = backingTexture
    }

    public static func make(
        pixelBuffer: CVPixelBuffer,
        textureCache: CVMetalTextureCache
    ) throws -> CapturedFrame {
        let sourceFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard sourceFormat == kCVPixelFormatType_32BGRA else {
            throw CaptureError.unsupportedPixelFormat(sourceFormat)
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else {
            throw CaptureError.textureCreationFailed(kCVReturnInvalidSize)
        }

        var coreVideoTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &coreVideoTexture
        )
        guard status == kCVReturnSuccess else {
            throw CaptureError.textureCreationFailed(status)
        }
        guard
            let coreVideoTexture,
            let texture = CVMetalTextureGetTexture(coreVideoTexture)
        else {
            throw CaptureError.textureCreationFailed(kCVReturnError)
        }

        return CapturedFrame(texture: texture, backingTexture: coreVideoTexture)
    }

    static func makeTextureCache(device: any MTLDevice) throws -> CVMetalTextureCache {
        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &cache
        )
        guard status == kCVReturnSuccess, let cache else {
            throw CaptureError.textureCacheCreationFailed(status)
        }
        return cache
    }
}
