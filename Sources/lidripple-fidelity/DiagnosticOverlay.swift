import Foundation

enum DiagnosticOverlay {
    static func make(frame: PixelFrame, signal: FrameSignal, mask: PixelMask) throws -> PixelFrame {
        precondition(frame.width == mask.width && frame.height == mask.height)
        var bytes = frame.bytes
        for y in 0..<frame.height {
            for x in 0..<frame.width where !mask.contains(x: x, y: y) {
                let offset = (y * frame.width + x) * 4
                bytes[offset] = UInt8(Double(bytes[offset]) * 0.35)
                bytes[offset + 1] = UInt8(Double(bytes[offset + 1]) * 0.35)
                bytes[offset + 2] = 220
            }
        }

        for y in [frame.height / 3, 2 * frame.height / 3] where y < frame.height {
            paintRow(y, blue: 40, green: 220, red: 40, in: &bytes, width: frame.width)
        }
        if signal.darkBoundary > 0 {
            let row = min(max(frame.height - Int((signal.darkBoundary * Double(frame.height)).rounded()), 0), frame.height - 1)
            paintRow(row, blue: 240, green: 210, red: 20, in: &bytes, width: frame.width)
        }
        return try PixelFrame(width: frame.width, height: frame.height, bytes: bytes)
    }

    private static func paintRow(
        _ row: Int,
        blue: UInt8,
        green: UInt8,
        red: UInt8,
        in bytes: inout [UInt8],
        width: Int
    ) {
        for x in 0..<width {
            let offset = (row * width + x) * 4
            bytes[offset] = blue
            bytes[offset + 1] = green
            bytes[offset + 2] = red
            bytes[offset + 3] = 255
        }
    }
}
