import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import LidRippleRenderer

private let goldenWidth = 320
private let goldenHeight = 200
private let goldenCases: [(name: String, progress: Double)] = [
    ("fold-p000", 0),
    ("fold-p025", 0.25),
    ("fold-p050", 0.50),
    ("fold-p075", 0.75),
    ("fold-p100", 1.00),
]

@Test func foldFramesMatchGoldenImages() throws {
    let context = try RendererTestContext()
    let source = try SyntheticFrame.makeCheckerboardGradientTexture(
        device: context.device,
        width: goldenWidth,
        height: goldenHeight
    )
    try context.renderer.setSource(texture: source)

    let environment = ProcessInfo.processInfo.environment
    if environment["LIDRIPPLE_RECORD_GOLDENS"] == "1" {
        let outputPath = try #require(environment["LIDRIPPLE_GOLDEN_OUTPUT_DIR"])
        let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
        for golden in goldenCases {
            let bytes = try context.render(
                progress: golden.progress,
                width: goldenWidth,
                height: goldenHeight
            )
            try writePNG(
                bytes: bytes,
                width: goldenWidth,
                height: goldenHeight,
                to: outputDirectory.appendingPathComponent("\(golden.name).png")
            )
        }
        return
    }

    for golden in goldenCases {
        let actual = try context.render(
            progress: golden.progress,
            width: goldenWidth,
            height: goldenHeight
        )
        let referenceURL = try #require(
            Bundle.module.url(forResource: golden.name, withExtension: "png")
        )
        let expected = try readPNG(
            at: referenceURL,
            width: goldenWidth,
            height: goldenHeight
        )
        let errors = zip(actual, expected).map { abs(Int($0) - Int($1)) }
        let maximumError = errors.max() ?? 0
        let meanError = Double(errors.reduce(0, +)) / Double(max(errors.count, 1))

        #expect(maximumError <= 2, "\(golden.name) maximum channel error was \(maximumError)/255")
        #expect(meanError <= 0.25, "\(golden.name) mean channel error was \(meanError)/255")
    }
}

private enum GoldenImageError: Error {
    case imageCreationFailed
    case destinationCreationFailed
    case destinationFinalizeFailed
    case sourceCreationFailed
    case wrongDimensions
    case bitmapContextCreationFailed
}

private func makeImage(bytes: [UInt8], width: Int, height: Int) throws -> CGImage {
    let data = Data(bytes) as CFData
    guard let provider = CGDataProvider(data: data) else {
        throw GoldenImageError.imageCreationFailed
    }
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
    )
    guard let image = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ) else {
        throw GoldenImageError.imageCreationFailed
    }
    return image
}

private func writePNG(bytes: [UInt8], width: Int, height: Int, to url: URL) throws {
    let image = try makeImage(bytes: bytes, width: width, height: height)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw GoldenImageError.destinationCreationFailed
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw GoldenImageError.destinationFinalizeFailed
    }
}

private func readPNG(at url: URL, width: Int, height: Int) throws -> [UInt8] {
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw GoldenImageError.sourceCreationFailed
    }
    guard image.width == width, image.height == height else {
        throw GoldenImageError.wrongDimensions
    }

    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
    )
    let madeContext = bytes.withUnsafeMutableBytes { storage -> CGContext? in
        CGContext(
            data: storage.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo.rawValue
        )
    }
    guard let context = madeContext else {
        throw GoldenImageError.bitmapContextCreationFailed
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return bytes
}
