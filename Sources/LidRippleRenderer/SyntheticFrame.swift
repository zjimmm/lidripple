import Metal
import Foundation

/// Permission-free source content used by golden tests and the development
/// scrubber. It is generated in memory and never contains captured user data.
public enum SyntheticFrame {
    /// Original procedural dusk landscape for the customer-facing preview.
    /// Fixed-size artwork avoids a native-resolution CPU loop on every preview.
    public static func makePreviewArtworkTexture(device: any MTLDevice) throws -> any MTLTexture {
        let width = 960
        let height = 600
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let v = Double(y) / Double(height - 1)
            for x in 0..<width {
                let u = Double(x) / Double(width - 1)
                var r = 32.0 + 150 * v
                var g = 48.0 + 88 * v
                var b = 85.0 + 42 * v
                let sun = hypot((u - 0.68) * 1.6, v - 0.32)
                let glow = exp(-sun * sun * 28)
                r += 60 * glow
                g += 37 * glow
                if sun < 0.075 { r = 249; g = 218; b = 172 }
                for ridge in 0..<4 {
                    let n = Double(ridge)
                    let horizon = 0.53 + n * 0.12 + 0.065 * sin(u * 7 + n * 1.9)
                        + 0.025 * sin(u * 16 + n)
                    if v > horizon {
                        let light = max(0, 1 - (v - horizon) * 3)
                        r = 32 + (3 - n) * 21 + light * 12
                        g = 52 + (3 - n) * 16 + light * 13
                        b = 69 + (3 - n) * 18 + light * 16
                    }
                }
                let index = (y * width + x) * 4
                bytes[index] = UInt8(min(max(b, 0), 255))
                bytes[index + 1] = UInt8(min(max(g, 0), 255))
                bytes[index + 2] = UInt8(min(max(r, 0), 255))
            }
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.textureAllocationFailed
        }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                        withBytes: bytes, bytesPerRow: width * 4)
        return texture
    }

    public static func checkerboardGradientBytes(width: Int, height: Int) -> [UInt8] {
        guard width > 0, height > 0 else { return [] }
        let blockSize = max(min(width, height) / 10, 1)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let checker = ((x / blockSize) + (y / blockSize)).isMultiple(of: 2) ? 42 : 0
                bytes[offset] = UInt8(min(255, x * 220 / max(width - 1, 1) + checker))
                bytes[offset + 1] = UInt8(min(255, y * 220 / max(height - 1, 1) + checker))
                bytes[offset + 2] = UInt8(min(
                    255,
                    (x + y) * 180 / max(width + height - 2, 1) + checker
                ))
                bytes[offset + 3] = 255
            }
        }
        return bytes
    }

    public static func makeCheckerboardGradientTexture(
        device: any MTLDevice,
        width: Int,
        height: Int
    ) throws -> any MTLTexture {
        let bytes = checkerboardGradientBytes(width: width, height: height)
        guard !bytes.isEmpty else { throw RendererError.textureAllocationFailed }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.textureAllocationFailed
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: width * 4
        )
        return texture
    }
}
