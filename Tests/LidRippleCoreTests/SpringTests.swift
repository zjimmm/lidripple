import Testing
import Foundation
@testable import LidRippleCore

@Test func settlesToItsTarget() {
    var spring = Spring(tuning: .default)
    for _ in 0..<120 { spring.step(target: 1.0, dt: 1.0 / 60.0) }
    #expect(abs(spring.value - 1.0) < 0.001)
    #expect(abs(spring.velocity) < 0.01)
}

@Test func overshootStaysWithinTheSpecMaximum() {
    var spring = Spring(tuning: .default)
    var peak = 0.0
    for _ in 0..<240 {
        spring.step(target: 1.0, dt: 1.0 / 60.0)
        peak = max(peak, spring.value)
    }
    // zeta = 26 / (2 * sqrt(220)) ~= 0.877, so unit-step overshoot is under 1%.
    #expect(peak > 1.0)
    #expect(peak < FoldTuning.default.maxProgress)
}

@Test func lagsBehindTheTargetRatherThanTrackingItExactly() {
    var spring = Spring(tuning: .default)
    spring.step(target: 1.0, dt: 1.0 / 60.0)
    #expect(spring.value < 0.2)      // this lag is what makes slow closes feel viscous
    #expect(spring.value > 0)
}

@Test func largeTimestepsStayStableBecauseOfFixedSubstepping() {
    var spring = Spring(tuning: .default)
    // A 250 ms hitch would explode a naive single-step Euler integrator.
    for _ in 0..<20 { spring.step(target: 1.0, dt: 0.25) }
    #expect(spring.value.isFinite)
    #expect(abs(spring.value - 1.0) < 0.01)
}

@Test func substeppingMakesTheResultIndependentOfSampleRate() {
    var at60 = Spring(tuning: .default)
    var at120 = Spring(tuning: .default)
    for _ in 0..<60 { at60.step(target: 1.0, dt: 1.0 / 60.0) }
    for _ in 0..<120 { at120.step(target: 1.0, dt: 1.0 / 120.0) }
    #expect(abs(at60.value - at120.value) < 0.01)
}

@Test func resetClearsValueAndVelocity() {
    var spring = Spring(tuning: .default)
    for _ in 0..<10 { spring.step(target: 1.0, dt: 1.0 / 60.0) }
    spring.reset(to: 0)
    #expect(spring.value == 0)
    #expect(spring.velocity == 0)
}
