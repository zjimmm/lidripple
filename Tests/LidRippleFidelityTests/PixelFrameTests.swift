import Foundation
import ImageIO
import Testing
@testable import lidripple_fidelity

@Test func sideBySidePlacesReferenceOnLeftAndRenderedOnRight() throws {
    let reference = try PixelFrame(width: 1, height: 2, bytes: [1, 2, 3, 255, 4, 5, 6, 255])
    let rendered = try PixelFrame(width: 1, height: 2, bytes: [7, 8, 9, 255, 10, 11, 12, 255])

    let result = try PixelFrame.sideBySide(reference: reference, rendered: rendered)

    #expect(result.width == 2)
    #expect(result.height == 2)
    #expect(result.bytes == [
        1, 2, 3, 255, 7, 8, 9, 255,
        4, 5, 6, 255, 10, 11, 12, 255,
    ])
}

@Test func pngAndAnimatedGIFAreWrittenWithExpectedFrameCounts() throws {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("lidripple-fidelity-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let first = try PixelFrame(width: 2, height: 1, bytes: [0, 0, 0, 255, 10, 20, 30, 255])
    let second = try PixelFrame(width: 2, height: 1, bytes: [40, 50, 60, 255, 70, 80, 90, 255])
    let png = temporary.appendingPathComponent("frame.png")
    let gif = temporary.appendingPathComponent("comparison.gif")

    try first.writePNG(to: png)
    try FidelityRun.writeGIF(frames: [first, second], duration: 0.62, to: gif)

    let pngSource = try #require(CGImageSourceCreateWithURL(png as CFURL, nil))
    let gifSource = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
    #expect(CGImageSourceGetCount(pngSource) == 1)
    #expect(CGImageSourceGetCount(gifSource) == 2)
    let fileProperties = try #require(CGImageSourceCopyProperties(gifSource, nil)) as NSDictionary
    let fileGIF = try #require(fileProperties[kCGImagePropertyGIFDictionary] as? NSDictionary)
    #expect((fileGIF[kCGImagePropertyGIFLoopCount] as? NSNumber)?.intValue == 0)
    let frameProperties = try #require(
        CGImageSourceCopyPropertiesAtIndex(gifSource, 0, nil)
    ) as NSDictionary
    let frameGIF = try #require(frameProperties[kCGImagePropertyGIFDictionary] as? NSDictionary)
    #expect(abs((frameGIF[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue ?? 0) - 0.62 < 0.001)
}

@Test func outputPreparationRefusesToDeleteExistingFiles() throws {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("lidripple-output-safety-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let existing = temporary.appendingPathComponent("frame-0000.png")
    try Data("owned by caller".utf8).write(to: existing)

    #expect(throws: FidelityError.outputDirectoryNotEmpty(temporary.path)) {
        try FidelityRun.prepareOutputDirectory(temporary)
    }
    #expect(try Data(contentsOf: existing) == Data("owned by caller".utf8))
}

@Test func comparisonCanvasIncludesExternalHeaderLabelsAndSynchronizedRuler() throws {
    let reference = try PixelFrame(width: 20, height: 10, bytes: [UInt8](repeating: 255, count: 800))
    let rendered = try PixelFrame(width: 20, height: 10, bytes: [UInt8](repeating: 64, count: 800))

    let canvas = try ComparisonCanvas.make(
        reference: reference,
        rendered: rendered,
        progress: 0.5,
        time: 0.31,
        duration: 0.62
    )

    #expect(ComparisonCanvas.referenceLabel == "Apple iPhone Duo reference")
    #expect(ComparisonCanvas.renderedLabel == "lidripple")
    #expect(canvas.width == 40)
    #expect(canvas.height == 10 + ComparisonCanvas.headerHeight + ComparisonCanvas.rulerHeight)
    #expect(Set(canvas.bytes).count > 3)
}

@Test func contactSheetUsesFixedColumnsAndPadsOnlyTheFinalRow() throws {
    let frames = try (1...3).map { value in
        try PixelFrame(width: 1, height: 1, bytes: [UInt8(value), 0, 0, 255])
    }

    let sheet = try PixelFrame.contactSheet(frames: frames, columns: 2)

    #expect(sheet.width == 2)
    #expect(sheet.height == 2)
    #expect(sheet.bytes == [
        1, 0, 0, 255, 2, 0, 0, 255,
        3, 0, 0, 255, 0, 0, 0, 0,
    ])
}
