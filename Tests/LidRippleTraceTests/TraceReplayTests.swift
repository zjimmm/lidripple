import Testing
import Foundation
@testable import LidRippleTrace
@testable import LidRippleCore

@Test func generatedTracesAreDeterministic() {
    #expect(TraceGenerator.slowClose() == TraceGenerator.slowClose())
    #expect(TraceGenerator.wiggleAtRest() == TraceGenerator.wiggleAtRest())
}

@Test func allSixCanonicalTracesExistAndAreNamed() {
    let names = Set(TraceGenerator.all.map(\.name))
    #expect(names == [
        "slow-close", "slam", "hesitant-close",
        "stop-and-reopen", "wiggle-at-rest", "close-reopen-close",
    ])
}

@Test func everyGeneratedTraceHasMonotonicTimestampsAndPlausibleAngles() {
    for trace in TraceGenerator.all {
        #expect(!trace.samples.isEmpty, "\(trace.name) is empty")
        for (a, b) in zip(trace.samples, trace.samples.dropFirst()) {
            #expect(b.t > a.t, "\(trace.name) has non-monotonic time")
        }
        for sample in trace.samples {
            #expect(sample.deg >= 0 && sample.deg <= 140, "\(trace.name) angle out of range")
        }
    }
}

@Test func slamIsMuchShorterThanSlowCloseForTheSameTravel() {
    let slow = TraceGenerator.slowClose()
    let slam = TraceGenerator.slam()
    let slowDuration = slow.samples.last!.t - slow.samples.first!.t
    let slamDuration = slam.samples.last!.t - slam.samples.first!.t
    #expect(slamDuration < slowDuration / 5)
}

@Test func wiggleAtRestStaysWithinAFractionOfADegree() {
    let samples = TraceGenerator.wiggleAtRest().samples
    let angles = samples.map(\.deg)
    #expect(angles.max()! - angles.min()! < 1.0)
}

@Test func replaySourceDeliversEverySampleInOrder() async throws {
    let trace = Trace(
        name: "tiny", recordedAt: Date(), deviceModel: "test",
        samples: (0..<20).map { .init(t: Double($0) / 60.0, deg: 100 - Double($0)) }
    )
    // 200x speed keeps the test fast while still exercising the timing path.
    let source = TraceReplaySource(trace: trace, speed: 200)
    let box = Box()
    try source.start { sample in box.append(sample) }

    let deadline = Date().addingTimeInterval(3)
    while box.count < 20, Date() < deadline {
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    source.stop()

    #expect(box.count == 20)
    #expect(box.degrees == (0..<20).map { 100 - Double($0) })
}

/// Minimal thread-safe collector, since the handler may fire off-thread.
private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [AngleSample] = []
    func append(_ s: AngleSample) { lock.lock(); samples.append(s); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return samples.count }
    var degrees: [Double] { lock.lock(); defer { lock.unlock() }; return samples.map(\.degrees) }
}

@Test func replaySourceIsAlwaysAvailable() {
    #expect(TraceReplaySource(trace: TraceGenerator.slam()).isAvailable)
}
