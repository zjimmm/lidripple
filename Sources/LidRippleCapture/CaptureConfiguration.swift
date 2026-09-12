import CoreGraphics
import CoreMedia
import CoreVideo
import ScreenCaptureKit

/// Builds the low-cost speculative stream used between the arm and fold angles.
public enum CaptureConfiguration {
    public static let warmFramesPerSecond: Int32 = 10

    public static func make(
        contentRect: CGRect,
        pointPixelScale: Float
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = pixelCount(
            points: contentRect.width,
            scale: CGFloat(pointPixelScale)
        )
        configuration.height = pixelCount(
            points: contentRect.height,
            scale: CGFloat(pointPixelScale)
        )
        configuration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: warmFramesPerSecond
        )
        configuration.queueDepth = 1
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.colorSpaceName = CGColorSpace.sRGB
        return configuration
    }

    private static func pixelCount(points: CGFloat, scale: CGFloat) -> Int {
        let pixels = points * scale
        guard pixels.isFinite else { return 1 }
        return max(Int(pixels.rounded()), 1)
    }
}
