import Testing
@testable import LidRippleRenderer

@Test func blueNoiseIsDeterministicAndUsesTheWholeEightBitHistogram() {
    let first = BlueNoise.bytes()
    let second = BlueNoise.bytes()

    #expect(first == second)
    #expect(first.count == 64 * 64)
    var counts = [Int](repeating: 0, count: 256)
    for value in first { counts[Int(value)] += 1 }
    #expect(counts.allSatisfy { $0 == 16 })
}

@Test func blueNoiseSuppressesImmediateNeighborCorrelation() {
    let bytes = BlueNoise.bytes().map { Double($0) / 255.0 - 0.5 }
    let size = BlueNoise.size
    var correlation = 0.0

    for y in 0..<size {
        for x in 0..<size {
            let value = bytes[y * size + x]
            let right = bytes[y * size + (x + 1) % size]
            let below = bytes[((y + 1) % size) * size + x]
            correlation += value * (right + below) * 0.5
        }
    }
    correlation /= Double(size * size)

    #expect(correlation < -0.01)
}
