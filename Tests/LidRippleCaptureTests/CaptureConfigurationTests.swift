import CoreGraphics
import CoreMedia
import CoreVideo
import ScreenCaptureKit
import Testing
@testable import LidRippleCapture

@Test func captureConfigurationUsesNativePixelDimensions() {
    let standard = CaptureConfiguration.make(
        contentRect: CGRect(x: 50, y: 20, width: 1470, height: 956),
        pointPixelScale: 1
    )
    #expect(standard.width == 1470)
    #expect(standard.height == 956)

    let retina = CaptureConfiguration.make(
        contentRect: CGRect(x: 0, y: 0, width: 1470, height: 956),
        pointPixelScale: 2
    )
    #expect(retina.width == 2940)
    #expect(retina.height == 1912)
}

@Test func captureConfigurationRoundsAndClampsPixelDimensions() {
    let rounded = CaptureConfiguration.make(
        contentRect: CGRect(x: 0, y: 0, width: 100.25, height: 50.24),
        pointPixelScale: 2
    )
    #expect(rounded.width == 201)
    #expect(rounded.height == 100)

    let clamped = CaptureConfiguration.make(contentRect: .zero, pointPixelScale: 0)
    #expect(clamped.width == 1)
    #expect(clamped.height == 1)
}

@Test func captureConfigurationIsCheapAndVideoOnly() {
    let configuration = CaptureConfiguration.make(
        contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
        pointPixelScale: 1
    )
    #expect(
        configuration.minimumFrameInterval
            == CMTime(value: 1, timescale: CaptureConfiguration.warmFramesPerSecond)
    )
    #expect(configuration.queueDepth == 1)
    #expect(configuration.pixelFormat == kCVPixelFormatType_32BGRA)
    #expect(!configuration.showsCursor)
    #expect(!configuration.capturesAudio)
    #expect(configuration.colorSpaceName == CGColorSpace.sRGB)
}
