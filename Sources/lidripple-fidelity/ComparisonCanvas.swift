import CoreGraphics
import CoreText
import Foundation

enum ComparisonCanvas {
    static let referenceLabel = "Apple iPhone Duo reference"
    static let renderedLabel = "lidripple"
    static let headerHeight = 38
    static let rulerHeight = 34

    static func make(
        reference: PixelFrame,
        rendered: PixelFrame,
        progress: Double,
        time: Double,
        duration: Double
    ) throws -> PixelFrame {
        guard reference.width == rendered.width, reference.height == rendered.height else {
            throw FidelityError.imageDimensionsInvalid
        }
        let width = reference.width * 2
        let height = headerHeight + reference.height + rulerHeight
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw FidelityError.bitmapContextCreationFailed
        }
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        try bytes.withUnsafeMutableBytes { storage in
            guard let context = CGContext(
                data: storage.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else { throw FidelityError.bitmapContextCreationFailed }

            context.setFillColor(CGColor(red: 0.055, green: 0.055, blue: 0.065, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .none
            context.draw(
                try reference.makeImage(),
                in: CGRect(x: 0, y: rulerHeight, width: reference.width, height: reference.height)
            )
            context.draw(
                try rendered.makeImage(),
                in: CGRect(x: reference.width, y: rulerHeight, width: rendered.width, height: rendered.height)
            )

            context.setStrokeColor(CGColor(gray: 0.30, alpha: 1))
            context.setLineWidth(1)
            context.move(to: CGPoint(x: reference.width, y: rulerHeight))
            context.addLine(to: CGPoint(x: reference.width, y: rulerHeight + reference.height))
            context.strokePath()

            let labelY = CGFloat(height - headerHeight + 12)
            drawText(referenceLabel, x: 14, y: labelY, in: context)
            drawText(renderedLabel, x: CGFloat(reference.width + 14), y: labelY, in: context)

            let clampedProgress = min(max(progress, 0), 1)
            let barStart: CGFloat = 14
            let barEnd = CGFloat(width - 14)
            let barY: CGFloat = 8
            context.setLineCap(.round)
            context.setLineWidth(4)
            context.setStrokeColor(CGColor(gray: 0.28, alpha: 1))
            context.move(to: CGPoint(x: barStart, y: barY))
            context.addLine(to: CGPoint(x: barEnd, y: barY))
            context.strokePath()
            context.setStrokeColor(CGColor(red: 0.26, green: 0.70, blue: 1, alpha: 1))
            context.move(to: CGPoint(x: barStart, y: barY))
            context.addLine(to: CGPoint(
                x: barStart + (barEnd - barStart) * clampedProgress,
                y: barY
            ))
            context.strokePath()
            drawText(
                String(format: "p %.3f    t %.3fs / %.3fs", progress, time, duration),
                x: 14,
                y: 16,
                in: context,
                size: 10
            )
        }
        return try PixelFrame(width: width, height: height, bytes: bytes)
    }

    private static func drawText(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        in context: CGContext,
        size: CGFloat = 13
    ) {
        let font = CTFontCreateWithName("SFMono-Semibold" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.92, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
    }
}
