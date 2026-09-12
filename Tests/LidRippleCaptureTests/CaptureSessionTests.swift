import ScreenCaptureKit
import Testing
@testable import LidRippleCapture

@Test func onlyCompleteScreenFramesAreAccepted() {
    #expect(SampleBufferFrameStatus.isComplete([.status: SCFrameStatus.complete.rawValue]))

    for status in [
        SCFrameStatus.idle,
        .blank,
        .suspended,
        .started,
        .stopped,
    ] {
        #expect(!SampleBufferFrameStatus.isComplete([.status: status.rawValue]))
    }
}

@Test func missingOrMalformedFrameStatusIsRejected() {
    #expect(!SampleBufferFrameStatus.isComplete([:]))
    #expect(!SampleBufferFrameStatus.isComplete([.status: "complete"]))
    #expect(SampleBufferFrameStatus.isComplete([
        .status: NSNumber(value: SCFrameStatus.complete.rawValue),
    ]))
}
