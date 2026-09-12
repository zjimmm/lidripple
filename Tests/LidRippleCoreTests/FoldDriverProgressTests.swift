import Testing
import Foundation
@testable import LidRippleCore

/// Sweeps and returns the peak progress seen, which is what most of these
/// tests actually care about.
private func sweepTrackingPeak(
    _ driver: FoldDriver,
    from: Double,
    to: Double,
    degreesPerSecond: Double,
    startingAt t0: TimeInterval
) -> (peak: Double, endTime: TimeInterval) {
    let hz = 60.0
    let step = degreesPerSecond / hz * (to > from ? 1 : -1)
    var angle = from
    var t = t0
    var peak = 0.0
    while (to > from && angle < to) || (to < from && angle > to) {
        angle += step
        t += 1 / hz
        peak = max(peak, driver.ingest(AngleSample(degrees: angle, timestamp: t)).progress)
    }
    return (peak, t)
}

@Test func progressIsZeroWhileIdleAndArmed() {
    let driver = FoldDriver()
    let (peak, _) = sweepTrackingPeak(driver, from: 130, to: 80, degreesPerSecond: 120, startingAt: 0)
    #expect(driver.state.phase == .armed)
    #expect(peak == 0)
}

@Test func aFullSlowCloseReachesFullProgress() {
    let driver = FoldDriver()
    // 40 deg/s is the spec's viscous case.
    sweepTrackingPeak(driver, from: 120, to: 15, degreesPerSecond: 40, startingAt: 0)
    #expect(driver.state.progress > 0.99)
}

@Test func progressNeverExceedsTheSpecMaximum() {
    for rate in [40.0, 120.0, 300.0, 600.0] {
        let driver = FoldDriver()
        let (peak, _) = sweepTrackingPeak(driver, from: 130, to: 5, degreesPerSecond: rate, startingAt: 0)
        #expect(peak <= FoldTuning.default.maxProgress + 1e-9, "rate \(rate) overshot to \(peak)")
    }
}

@Test func feedForwardMakesAFastCloseLeadPureAngleTracking() {
    let withFeedForward = FoldDriver(tuning: .default)
    var noFeedForwardTuning = FoldTuning.default
    noFeedForwardTuning.feedForward = 0
    let withoutFeedForward = FoldDriver(tuning: noFeedForwardTuning)

    // Same rate, same path, same driver clock — isolates feed-forward's effect
    // directly, rather than comparing two differently-paced sweeps. (A sweep
    // 10x shorter in wall-clock time can never catch up to a much longer
    // sweep's accumulated progress regardless of feed-forward magnitude,
    // since the spring's output is bounded by elapsed integration time —
    // see the task report for the full analysis.)
    sweepTrackingPeak(withFeedForward, from: 120, to: 50, degreesPerSecond: 400, startingAt: 0)
    sweepTrackingPeak(withoutFeedForward, from: 120, to: 50, degreesPerSecond: 400, startingAt: 0)
    #expect(withFeedForward.state.progress > withoutFeedForward.state.progress)
}

@Test func reversingMidCloseNeverReachesFullProgress() {
    let driver = FoldDriver()
    let (peakIn, t) = sweepTrackingPeak(driver, from: 120, to: 40, degreesPerSecond: 120, startingAt: 0)
    #expect(peakIn < 1.0)
    let (_, t2) = sweepTrackingPeak(driver, from: 40, to: 95, degreesPerSecond: 120, startingAt: t)
    // Settle at the open angle.
    var t3 = t2
    for _ in 0..<60 { t3 += 1 / 60.0; driver.ingest(AngleSample(degrees: 95, timestamp: t3)) }
    #expect(driver.state.phase == .idle)
    #expect(driver.state.progress == 0)
}

@Test func progressIsMonotonicDuringASteadyClose() {
    let driver = FoldDriver()
    var previous = -1.0
    var angle = 120.0
    var t = 0.0
    var sawDecrease = false
    while angle > 20 {
        angle -= 2
        t += 1 / 60.0
        let p = driver.ingest(AngleSample(degrees: angle, timestamp: t)).progress
        if p < previous - 1e-9 { sawDecrease = true }
        previous = p
    }
    #expect(!sawDecrease)
}

@Test func tickAdvancesProgressWithoutNewSamples() {
    let driver = FoldDriver()
    let (_, t) = sweepTrackingPeak(driver, from: 120, to: 40, degreesPerSecond: 120, startingAt: 0)
    let before = driver.state.progress
    var now = t
    for _ in 0..<10 { now += 1 / 120.0; driver.tick(now: now) }
    // The spring is still chasing the target set by the last real sample.
    #expect(driver.state.progress > before)
}

@Test func scriptedUnfoldRunsFromSealedToZeroInExactlyTheSpecifiedTime() {
    let driver = FoldDriver()
    driver.signalSleep()
    #expect(driver.state.progress == 1.0)

    var now = 100.0
    driver.beginScriptedUnfold(now: now)
    #expect(driver.state.phase == .unfolding)

    let duration = FoldTuning.default.scriptedUnfoldSeconds

    // Smoothstep is symmetric, so halfway through time is halfway through progress.
    while now < 100 + duration / 2 { now += 1 / 240.0; driver.tick(now: now) }
    #expect(abs(driver.state.progress - 0.5) < 0.05)
    #expect(driver.state.velocity < 0)

    // At the deadline it is finished outright, with no spring tail.
    while now < 100 + duration + 1 / 60.0 { now += 1 / 240.0; driver.tick(now: now) }
    #expect(driver.state.phase == .idle)
    #expect(driver.state.progress == 0)
}

@Test func signalSleepDuringScriptedUnfoldStaysSealedOnNextTick() {
    let driver = FoldDriver()
    driver.signalSleep()
    driver.beginScriptedUnfold(now: 100)
    driver.tick(now: 100.1)
    #expect(driver.state.phase == .unfolding)

    // Sleep interrupts the scripted unfold; it must report sealed immediately...
    let sealed = driver.signalSleep()
    #expect(sealed.phase == .sealed)
    #expect(sealed.progress == 1.0)

    // ...and the seal must hold on the next tick, rather than the leftover
    // scriptedUnfoldStart resurrecting the unfold and dropping back to idle.
    let after = driver.tick(now: 101.0)
    #expect(after.phase == .sealed)
    #expect(after.progress == 1.0)
}

@Test func ingestDuringScriptedUnfoldTracksRealAngleInsteadOfCorruptingProgress() {
    let driver = FoldDriver()
    driver.signalSleep()
    var now = 100.0
    driver.beginScriptedUnfold(now: now)

    // Let the scripted curve run partway.
    now += 0.2
    let before = driver.tick(now: now).progress
    #expect(before > 0 && before < 1)

    // A real angle sample arrives mid-unfold (e.g. the lid is already fully
    // open). Progress must continue smoothly toward 0 from wherever the
    // scripted curve left off -- not jump backward past 0 and snap back up,
    // the way the pre-fix bug did (0.930 -> 0.476 -> 0.643 on one sample).
    var previous = before
    var sawIncrease = false
    for _ in 0..<40 {
        now += 1 / 60.0
        let p = driver.ingest(AngleSample(degrees: 130, timestamp: now)).progress
        if p > previous + 1e-9 { sawIncrease = true }
        previous = p
    }
    #expect(!sawIncrease, "progress must not increase while the real angle stays fully open")
    #expect(driver.state.phase == .idle)
    #expect(driver.state.progress == 0)
}

@Test func velocityIsReportedAndOppositelySignedInEachDirection() {
    let driver = FoldDriver()
    let (_, t) = sweepTrackingPeak(driver, from: 120, to: 50, degreesPerSecond: 200, startingAt: 0)
    #expect(driver.state.velocity > 0)      // folding: progress increasing
    sweepTrackingPeak(driver, from: 50, to: 70, degreesPerSecond: 200, startingAt: t)
    #expect(driver.state.velocity < 0)      // unfolding: progress decreasing
}
