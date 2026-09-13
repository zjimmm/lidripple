import Testing
@testable import lidripple_fidelity

@Test func fixedProjectiveCropMapsAllFourPanelCorners() throws {
    let bytes = (0..<16).reduce(into: [UInt8]()) { result, value in
        result.append(contentsOf: [UInt8(value), 0, 0, 255])
    }
    let source = try PixelFrame(width: 4, height: 4, bytes: bytes)
    let alignment = PanelAlignment(
        outputWidth: 2,
        outputHeight: 2,
        displayCorners: .init(
            topLeft: .init(x: 1, y: 1),
            topRight: .init(x: 2, y: 1),
            bottomRight: .init(x: 2, y: 2),
            bottomLeft: .init(x: 1, y: 2)
        ),
        exclusionPolygons: []
    )

    let corrected = try alignment.correct(source)

    #expect(corrected.width == 2)
    #expect(corrected.height == 2)
    #expect(stride(from: 0, to: corrected.bytes.count, by: 4).map { corrected.bytes[$0] }
        == [5, 6, 9, 10])
}

@Test func exclusionPolygonRemovesMaskedPixelsFromSobelAndOverlayMarksThem() throws {
    let alignment = PanelAlignment(
        outputWidth: 5,
        outputHeight: 5,
        displayCorners: .init(
            topLeft: .init(x: 0, y: 0),
            topRight: .init(x: 4, y: 0),
            bottomRight: .init(x: 4, y: 4),
            bottomLeft: .init(x: 0, y: 4)
        ),
        exclusionPolygons: [[
            .init(x: 0, y: 0), .init(x: 0.5, y: 0),
            .init(x: 0.5, y: 0.5), .init(x: 0, y: 0.5),
        ]]
    )
    let mask = alignment.measurementMask()
    #expect(!mask.contains(x: 1, y: 1))
    #expect(mask.contains(x: 4, y: 4))

    let frame = try PixelFrame(
        width: 5,
        height: 5,
        bytes: [UInt8](repeating: 255, count: 5 * 5 * 4)
    )
    let signal = FrameSignal.measure(frame, mask: mask)
    #expect(signal.edgeSampleFractions.contains { $0 < 1 })
    let overlay = try DiagnosticOverlay.make(frame: frame, signal: signal, mask: mask)
    // Pick a masked pixel that is not also one of the diagnostic band rows;
    // band guides intentionally take visual precedence where they intersect.
    let maskedOffset = (0 * 5 + 1) * 4
    #expect(overlay.bytes[maskedOffset + 2] == 220)
}
