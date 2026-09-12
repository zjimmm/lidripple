import Metal

/// A deterministic, rank-normalized high-pass noise tile. Ranking restores a
/// uniform 8-bit histogram after the Laplacian removes low spatial frequencies,
/// giving the dark gradient dither a blue-noise spectrum without a bundled asset.
enum BlueNoise {
    static let size = 64

    static func bytes() -> [UInt8] {
        var generator = XorShift32(state: 0x6D2B_79F5)
        var white = [Float](repeating: 0, count: size * size)
        for index in white.indices {
            white[index] = Float(generator.next()) / Float(UInt32.max)
        }

        func value(x: Int, y: Int) -> Float {
            let wrappedX = (x + size) % size
            let wrappedY = (y + size) % size
            return white[wrappedY * size + wrappedX]
        }

        var scores = [Float](repeating: 0, count: white.count)
        for y in 0..<size {
            for x in 0..<size {
                let index = y * size + x
                let neighborMean = (
                    value(x: x - 1, y: y)
                    + value(x: x + 1, y: y)
                    + value(x: x, y: y - 1)
                    + value(x: x, y: y + 1)
                ) * 0.25
                scores[index] = white[index] - neighborMean
            }
        }

        let rankedIndices = scores.indices.sorted {
            if scores[$0] == scores[$1] { return $0 < $1 }
            return scores[$0] < scores[$1]
        }
        var result = [UInt8](repeating: 0, count: scores.count)
        for (rank, index) in rankedIndices.enumerated() {
            result[index] = UInt8(rank * 256 / rankedIndices.count)
        }
        return result
    }

    static func makeTexture(device: any MTLDevice) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.textureAllocationFailed
        }
        let bytes = bytes()
        texture.replace(
            region: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: size
        )
        texture.label = "lidripple blue noise"
        return texture
    }
}

private struct XorShift32 {
    var state: UInt32

    mutating func next() -> UInt32 {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return state
    }
}
