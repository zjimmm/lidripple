import Testing
import Foundation
@testable import LidRippleCore

/// Drives a driver from `from` to `to` degrees at a given rate, 60 Hz.
/// Returns every state produced, so tests can assert on the whole trajectory.
@discardableResult
private func sweep(
    _ driver: FoldDriver,
    from: Double,
    to: Double,
    degreesPerSecond: Double,
    startingAt t0: TimeInterval
) -> (states: [FoldState], endTime: TimeInterval) {
    let hz = 60.0
    let step = degreesPerSecond / hz * (to > from ? 1 : -1)
    var angle = from
    var t = t0
    var states: [FoldState] = []
    while (to > from && angle < to) || (to < from && angle > to) {
        angle += step
        t += 1 / hz
        states.append(driver.ingest(AngleSample(degrees: angle, timestamp: t)))
    }
    return (states, t)
}

/// Holds a constant angle, which is how a direction gate gets time to expire.
@discardableResult
private func hold(
    _ driver: FoldDriver,
    at angle: Double,
    seconds: Double,
    startingAt t0: TimeInterval
) -> TimeInterval {
    var t = t0
    for _ in 0..<Int(seconds * 60) {
        t += 1 / 60.0
        driver.ingest(AngleSample(degrees: angle, timestamp: t))
    }
    return t
}

@Test func startsIdle() {
    #expect(FoldDriver().state.phase == .idle)
}

@Test func aSingleSampleBelowArmAngleDoesNotArm() {
    let driver = FoldDriver()
    // No previous sample means no velocity, so intent cannot be established.
    driver.ingest(AngleSample(degrees: 100, timestamp: 0))
    #expect(driver.state.phase == .idle)
}

@Test func sustainedClosingBelowArmAngleArms() {
    let driver = FoldDriver()
    sweep(driver, from: 120, to: 100, degreesPerSecond: 120, startingAt: 0)
    #expect(driver.state.phase == .armed)
}

@Test func armedBecomesFoldingBelowFoldStart() {
    let driver = FoldDriver()
    sweep(driver, from: 120, to: 70, degreesPerSecond: 120, startingAt: 0)
    #expect(driver.state.phase == .folding)
}

@Test func foldingBecomesSealedBelowSealAngle() {
    let driver = FoldDriver()
    sweep(driver, from: 120, to: 8, degreesPerSecond: 120, startingAt: 0)
    #expect(driver.state.phase == .sealed)
}

@Test func physicalSealCanReopenAngleTrackedInClamshellMode() {
    let driver = FoldDriver()
    let (_, sealedAt) = sweep(
        driver,
        from: 120,
        to: 8,
        degreesPerSecond: 120,
        startingAt: 0
    )
    #expect(driver.state.phase == .sealed)

    sweep(driver, from: 8, to: 35, degreesPerSecond: 120, startingAt: sealedAt)
    #expect(driver.state.phase == .unfolding)
    #expect(driver.state.progress < 1)
}

@Test func systemSealIgnoresAngleUntilExplicitUnlockOrReset() {
    let driver = FoldDriver()
    driver.signalSleep()
    sweep(driver, from: 8, to: 100, degreesPerSecond: 120, startingAt: 0)

    #expect(driver.state.phase == .sealed)
    #expect(driver.state.progress == 1)
}

@Test func aSingleOpeningSampleDoesNotReverseTheFold() {
    let driver = FoldDriver()
    let (_, t) = sweep(driver, from: 120, to: 50, degreesPerSecond: 120, startingAt: 0)
    #expect(driver.state.phase == .folding)
    // One sample of opening is noise, not intent.
    driver.ingest(AngleSample(degrees: 50.5, timestamp: t + 1 / 60.0))
    #expect(driver.state.phase == .folding)
}

@Test func sustainedOpeningReversesTheFold() {
    let driver = FoldDriver()
    let (_, t) = sweep(driver, from: 120, to: 50, degreesPerSecond: 120, startingAt: 0)
    sweep(driver, from: 50, to: 62, degreesPerSecond: 120, startingAt: t)
    #expect(driver.state.phase == .unfolding)
}

@Test func unfoldingDoesNotReturnToIdleBelowTheHysteresisThreshold() {
    let driver = FoldDriver()
    let (_, t1) = sweep(driver, from: 120, to: 50, degreesPerSecond: 120, startingAt: 0)
    let (_, t2) = sweep(driver, from: 50, to: 77, degreesPerSecond: 120, startingAt: t1)
    // 77 is above fold start (75) but below idle return (78).
    hold(driver, at: 77, seconds: 0.6, startingAt: t2)
    #expect(driver.state.phase == .unfolding)
}

@Test func unfoldingReturnsToIdleAboveTheHysteresisThreshold() {
    let driver = FoldDriver()
    let (_, t1) = sweep(driver, from: 120, to: 50, degreesPerSecond: 120, startingAt: 0)
    let (_, t2) = sweep(driver, from: 50, to: 85, degreesPerSecond: 120, startingAt: t1)
    hold(driver, at: 85, seconds: 0.6, startingAt: t2)
    #expect(driver.state.phase == .idle)
    #expect(driver.state.progress == 0)
}

@Test func jitterAtRestNeverChangesPhase() {
    let driver = FoldDriver()
    var t = 0.0
    for i in 0..<600 {
        t += 1 / 60.0
        driver.ingest(AngleSample(degrees: 90 + (i % 2 == 0 ? 0.25 : -0.25), timestamp: t))
        #expect(driver.state.phase == .idle)
    }
}

@Test func sleepSignalSealsFromAnyPhase() {
    for endAngle in [90.0, 100.0, 50.0] {
        let driver = FoldDriver()
        sweep(driver, from: 130, to: endAngle, degreesPerSecond: 120, startingAt: 0)
        let state = driver.signalSleep()
        #expect(state.phase == .sealed)
        #expect(state.progress == 1.0)
    }
}

@Test func resetReturnsToIdleWithZeroProgress() {
    let driver = FoldDriver()
    sweep(driver, from: 120, to: 40, degreesPerSecond: 120, startingAt: 0)
    let state = driver.reset()
    #expect(state.phase == .idle)
    #expect(state.progress == 0)
}
