import Foundation
import Testing
@testable import lidripple_fidelity

@Test func pngDirectoryUsesDeterministicLexicalOrderAndEndpointPreservingResampling() async throws {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("lidripple-reference-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }

    for (name, value) in [("frame-0010.png", UInt8(30)), ("frame-0002.png", 20), ("frame-0001.png", 10)] {
        let frame = try PixelFrame(width: 1, height: 1, bytes: [value, value, value, 255])
        try frame.writePNG(to: temporary.appendingPathComponent(name))
    }

    let result = try await ReferenceSequence.load(
        from: temporary,
        frameCount: 5,
        duration: 1.25
    )

    #expect(result.duration == 1.25)
    #expect(result.frames.count == 5)
    #expect(result.frames.map { $0.bytes[0] } == [10, 20, 20, 30, 30])
}
