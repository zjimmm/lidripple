import Testing
import Foundation
@testable import LidRippleTrace
@testable import LidRippleCore

@Test func roundTripsThroughJSON() throws {
    let trace = Trace(
        name: "slow-close",
        recordedAt: Date(timeIntervalSince1970: 1_789_000_000),
        deviceModel: "MacBookPro18,3",
        samples: [.init(t: 0, deg: 95.25), .init(t: 1.0 / 60.0, deg: 94.5)]
    )
    let decoded = try Trace.decoded(from: try trace.encoded())
    #expect(decoded == trace)
}

@Test func encodedJSONUsesTheShortStableKeys() throws {
    let trace = Trace(
        name: "x", recordedAt: Date(timeIntervalSince1970: 0), deviceModel: "m",
        samples: [.init(t: 0.5, deg: 90)]
    )
    let json = String(decoding: try trace.encoded(), as: UTF8.self)
    // A trace is tens of thousands of samples; short keys keep fixtures readable.
    #expect(json.contains("\"t\""))
    #expect(json.contains("\"deg\""))
}

@Test func angleSamplesAreRebasedToStartAtZero() {
    let trace = Trace(
        name: "x", recordedAt: Date(), deviceModel: "m",
        samples: [.init(t: 5000.0, deg: 95), .init(t: 5000.5, deg: 90)]
    )
    let samples = trace.angleSamples
    #expect(samples[0].timestamp == 0)
    #expect(abs(samples[1].timestamp - 0.5) < 1e-12)
    #expect(samples[0].degrees == 95)
}

@Test func anEmptyTraceProducesNoSamples() {
    let trace = Trace(name: "x", recordedAt: Date(), deviceModel: "m", samples: [])
    #expect(trace.angleSamples.isEmpty)
}

@Test func recorderAccumulatesSamplesInOrder() {
    let recorder = TraceRecorder(name: "slam", deviceModel: "MacBookPro18,3")
    recorder.record(AngleSample(degrees: 95, timestamp: 10))
    recorder.record(AngleSample(degrees: 90, timestamp: 10.5))
    #expect(recorder.count == 2)

    let trace = recorder.finish(at: Date(timeIntervalSince1970: 0))
    #expect(trace.name == "slam")
    #expect(trace.deviceModel == "MacBookPro18,3")
    #expect(trace.samples.map(\.deg) == [95, 90])
    #expect(trace.samples.map(\.t) == [10, 10.5])
}
