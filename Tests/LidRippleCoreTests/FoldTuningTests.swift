import Testing
import Foundation
@testable import LidRippleCore

@Test func defaultsMatchTheSpec() {
    let t = FoldTuning.default
    #expect(t.armAngle == 110)
    #expect(t.foldStartAngle == 75)
    #expect(t.foldEndAngle == 25)
    #expect(t.sealAngle == 12)
    #expect(t.idleReturnAngle == 78)
    #expect(t.directionVelocityThreshold == 5)
    #expect(t.directionHoldSeconds == 0.050)
    #expect(t.filterCutoffHz == 15)
    #expect(t.deadbandDegrees == 0.3)
    #expect(t.stiffness == 220)
    #expect(t.damping == 26)
    #expect(t.feedForward == 0.06)
    #expect(t.maxProgress == 1.06)
    #expect(t.substepSeconds == 1.0 / 240.0)
    #expect(t.rotationDegrees == 72)
    #expect(t.blurRadiusPx == 28)
    #expect(t.voidSpeed == 1.15)
    #expect(t.intensity == 1.0)
}

@Test func idleReturnIsAboveFoldStartByTheHysteresisGap() {
    let t = FoldTuning.default
    #expect(t.idleReturnAngle - t.foldStartAngle == t.phaseHysteresisDegrees)
}

@Test func intensityScalesOnlyTheThreeRenderTerms() {
    let base = FoldTuning.default
    let soft = base.withIntensity(0.5)

    // Scaled, per spec FR-17.
    #expect(soft.blurRadiusPx == base.blurRadiusPx * 0.5)
    #expect(soft.rotationDegrees == base.rotationDegrees * 0.5)
    #expect(soft.squashExponentGain == base.squashExponentGain * 0.5)

    // Untouched: timing, thresholds, spring.
    #expect(soft.foldStartAngle == base.foldStartAngle)
    #expect(soft.foldEndAngle == base.foldEndAngle)
    #expect(soft.stiffness == base.stiffness)
    #expect(soft.damping == base.damping)
    #expect(soft.substepSeconds == base.substepSeconds)
    #expect(soft.directionHoldSeconds == base.directionHoldSeconds)
}

@Test func intensityClampsToTheSupportedRange() {
    #expect(FoldTuning.default.withIntensity(0.1).intensity == 0.5)
    #expect(FoldTuning.default.withIntensity(9.0).intensity == 1.0)
}

@Test func withIntensityScalesFromCurrentValuesNotHardcodedDefaults() throws {
    var t = FoldTuning.default
    try t.apply(overrides: ["blurRadiusPx": 40])
    let scaled = t.withIntensity(0.5)
    #expect(scaled.blurRadiusPx == 20)  // 40 * 0.5, not FoldTuning.default.blurRadiusPx * 0.5
}

@Test func partialOverridesLeaveEverythingElseAtDefault() throws {
    var t = FoldTuning.default
    try t.apply(overrides: ["stiffness": 300, "blurRadiusPx": 40])
    #expect(t.stiffness == 300)
    #expect(t.blurRadiusPx == 40)
    #expect(t.damping == FoldTuning.default.damping)
    #expect(t.foldStartAngle == FoldTuning.default.foldStartAngle)
}

@Test func unknownOverrideKeyIsRejectedRatherThanIgnored() {
    var t = FoldTuning.default
    #expect(throws: FoldTuningError.unknownKey("stifness")) {
        try t.apply(overrides: ["stifness": 300])
    }
}

@Test func roundTripsThroughJSON() throws {
    let original = FoldTuning.default.withIntensity(0.75)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(FoldTuning.self, from: data)
    #expect(decoded == original)
}
