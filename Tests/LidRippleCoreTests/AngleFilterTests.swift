import Testing
import Foundation
@testable import LidRippleCore

/// Feeds a filter a sequence of angles at a fixed rate.
private func feed(
    _ filter: inout AngleFilter,
    angles: [Double],
    hz: Double = 60,
    startingAt t0: TimeInterval = 0
) -> [Double] {
    var out: [Double] = []
    for (i, deg) in angles.enumerated() {
        out.append(filter.process(AngleSample(degrees: deg, timestamp: t0 + Double(i) / hz)))
    }
    return out
}

@Test func firstSampleIsPassedThroughWithZeroVelocity() {
    var filter = AngleFilter(tuning: .default)
    let committed = filter.process(AngleSample(degrees: 91.4, timestamp: 0))
    #expect(committed == 91.4)
    #expect(filter.velocity == 0)
}

@Test func constantInputSettlesToThatValueWithZeroVelocity() {
    var filter = AngleFilter(tuning: .default)
    let out = feed(&filter, angles: Array(repeating: 90, count: 60))
    #expect(abs(out.last! - 90) < 0.001)
    #expect(abs(filter.velocity) < 0.1)
}

@Test func aStepIsSmoothedRatherThanJumped() {
    var filter = AngleFilter(tuning: .default)
    _ = feed(&filter, angles: Array(repeating: 90, count: 30))
    let out = feed(&filter, angles: Array(repeating: 60, count: 2), startingAt: 0.5)
    // 15 Hz one-pole at 60 Hz has alpha ~= 0.79, so a 30 degree step must not
    // arrive whole on the first sample.
    #expect(out[0] > 60.5)
    #expect(out[0] < 90)
}

@Test func subDeadbandJitterNeverMovesTheCommittedAngle() {
    var filter = AngleFilter(tuning: .default)
    var angles = [90.0]
    // Deterministic alternating jitter well inside the 0.3 degree deadband.
    for i in 0..<120 { angles.append(90 + (i % 2 == 0 ? 0.12 : -0.12)) }
    let out = feed(&filter, angles: angles)
    #expect(out.allSatisfy { $0 == 90.0 })
}

@Test func jitterAtRestKeepsSmoothedVelocityBelowTheDirectionGate() {
    var filter = AngleFilter(tuning: .default)
    var angles = [90.0]
    for i in 0..<120 { angles.append(90 + (i % 2 == 0 ? 0.25 : -0.25)) }
    _ = feed(&filter, angles: angles)
    // This is plan deviation 1: without velocity smoothing this exceeds 5.
    #expect(abs(filter.velocity) < FoldTuning.default.directionVelocityThreshold)
}

@Test func steadyRampConvergesToTheRampRate() {
    var filter = AngleFilter(tuning: .default)
    let ratePerSecond = -120.0            // closing at 120 deg/s
    let angles = (0..<90).map { 110 + ratePerSecond * Double($0) / 60.0 }
    _ = feed(&filter, angles: angles)
    #expect(abs(filter.velocity - ratePerSecond) < 6.0)
}

@Test func invalidAndReorderedSamplesDoNotPoisonSubsequentMotion() {
    var reference = AngleFilter(tuning: .default)
    var noisy = AngleFilter(tuning: .default)
    _ = noisy.process(.init(degrees: .nan, timestamp: 0))
    for index in 0..<60 {
        let time = Double(index) / 60
        let sample = AngleSample(degrees: 110 - Double(index), timestamp: time)
        #expect(noisy.process(sample) == reference.process(sample))
        let velocity = reference.velocity
        for invalid in [
            AngleSample(degrees: .infinity, timestamp: time + 0.001),
            AngleSample(degrees: 0, timestamp: .nan),
            AngleSample(degrees: 0, timestamp: time),
            AngleSample(degrees: 0, timestamp: time - 1),
        ] { _ = noisy.process(invalid) }
        #expect(noisy.velocity == velocity)
    }
}
