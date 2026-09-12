import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PixelFrame: Equatable, Sendable {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(width: Int, height: Int, bytes: [UInt8]) throws {
        guard width > 0, height > 0, bytes.count == width * height * 4 else {
            throw FidelityError.imageDimensionsInvalid
        }
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    init(image: CGImage, width: Int? = nil, height: Int? = nil) throws {
        let targetWidth = width ?? image.width
        let targetHeight = height ?? image.height
        guard targetWidth > 0, targetHeight > 0 else {
            throw FidelityError.imageDimensionsInvalid
        }
        var bytes = [UInt8](repeating: 0, count: targetWidth * targetHeight * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw FidelityError.bitmapContextCreationFailed
        }
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        let context = bytes.withUnsafeMutableBytes { storage in
            CGContext(
                data: storage.baseAddress,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: targetWidth * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            )
        }
        guard let context else { throw FidelityError.bitmapContextCreationFailed }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        try self.init(width: targetWidth, height: targetHeight, bytes: bytes)
    }

    static func readPNG(at url: URL, width: Int? = nil, height: Int? = nil) throws -> PixelFrame {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw FidelityError.imageReadFailed(url.path)
        }
        return try PixelFrame(image: image, width: width, height: height)
    }

    func writePNG(to url: URL) throws {
        let image = try makeImage()
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw FidelityError.imageWriteFailed(url.path) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FidelityError.imageWriteFailed(url.path)
        }
    }

    func resized(width: Int, height: Int) throws -> PixelFrame {
        if width == self.width, height == self.height { return self }
        return try PixelFrame(image: makeImage(), width: width, height: height)
    }

    static func sideBySide(reference: PixelFrame, rendered: PixelFrame) throws -> PixelFrame {
        guard reference.width == rendered.width, reference.height == rendered.height else {
            throw FidelityError.imageDimensionsInvalid
        }
        let combinedWidth = reference.width * 2
        var combined = [UInt8](repeating: 0, count: combinedWidth * reference.height * 4)
        for row in 0..<reference.height {
            let sourceStart = row * reference.width * 4
            let sourceEnd = sourceStart + reference.width * 4
            let destinationStart = row * combinedWidth * 4
            combined.replaceSubrange(
                destinationStart..<(destinationStart + reference.width * 4),
                with: reference.bytes[sourceStart..<sourceEnd]
            )
            combined.replaceSubrange(
                (destinationStart + reference.width * 4)..<(destinationStart + combinedWidth * 4),
                with: rendered.bytes[sourceStart..<sourceEnd]
            )
        }
        return try PixelFrame(width: combinedWidth, height: reference.height, bytes: combined)
    }

    static func contactSheet(frames: [PixelFrame], columns: Int = 5) throws -> PixelFrame {
        guard let first = frames.first, columns > 0 else {
            throw FidelityError.imageDimensionsInvalid
        }
        guard frames.allSatisfy({ $0.width == first.width && $0.height == first.height }) else {
            throw FidelityError.imageDimensionsInvalid
        }
        let usedColumns = min(columns, frames.count)
        let rows = (frames.count + usedColumns - 1) / usedColumns
        let sheetWidth = first.width * usedColumns
        let sheetHeight = first.height * rows
        var bytes = [UInt8](repeating: 0, count: sheetWidth * sheetHeight * 4)
        for (index, frame) in frames.enumerated() {
            let column = index % usedColumns
            let row = index / usedColumns
            for frameRow in 0..<first.height {
                let sourceStart = frameRow * first.width * 4
                let sourceEnd = sourceStart + first.width * 4
                let destinationStart = ((row * first.height + frameRow) * sheetWidth + column * first.width) * 4
                bytes.replaceSubrange(
                    destinationStart..<(destinationStart + first.width * 4),
                    with: frame.bytes[sourceStart..<sourceEnd]
                )
            }
        }
        return try PixelFrame(width: sheetWidth, height: sheetHeight, bytes: bytes)
    }

    func makeImage() throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw FidelityError.bitmapContextCreationFailed
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
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { throw FidelityError.bitmapContextCreationFailed }
        return image
    }
}
