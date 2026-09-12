import CoreGraphics
import Testing
@testable import LidRippleCapture

@Test func captureErrorsPreserveTargetIdentifiers() {
    #expect(CaptureError.displayNotFound(42) == .displayNotFound(42))
    #expect(CaptureError.excludedWindowNotFound(7) == .excludedWindowNotFound(7))
}
