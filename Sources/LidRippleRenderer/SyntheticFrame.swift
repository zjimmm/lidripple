import Metal

/// Permission-free source content used by golden tests and the development
/// scrubber. It is generated in memory and never contains captured user data.
public enum SyntheticFrame {
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
