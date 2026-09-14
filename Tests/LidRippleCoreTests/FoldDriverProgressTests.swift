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
    _ = sweepTrackingPeak(driver, from: 120, to: 15, degreesPerSecond: 40, startingAt: 0)
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
    _ = sweepTrackingPeak(withFeedForward, from: 120, to: 50, degreesPerSecond: 400, startingAt: 0)
    _ = sweepTrackingPeak(withoutFeedForward, from: 120, to: 50, degreesPerSecond: 400, startingAt: 0)
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

@Test func anOlderDisplayTimestampCannotDoubleIntegrateTheSpring() {
    let reference = FoldDriver()
    let reordered = FoldDriver()
    for driver in [reference, reordered] {
        driver.ingest(.init(degrees: 120, timestamp: 0))
        driver.ingest(.init(degrees: 100, timestamp: 0.1))
        driver.ingest(.init(degrees: 60, timestamp: 0.2))
        driver.tick(now: 0.216)
    }

    // A callback queued before the last frame can arrive afterward. It must
    // not rewind the integration clock and make the next frame jump forward.
    reordered.tick(now: 0.15)
    let actual = reordered.tick(now: 0.232)
    let expected = reference.tick(now: 0.232)
    #expect(abs(actual.progress - expected.progress) < 1e-9)
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

@Test func firstPostUnlockAngleStartsAtTheCurrentLidPose() {
    let driver = FoldDriver()
    driver.signalSleep()
    driver.beginScriptedUnfold(now: 10)

    let aligned = driver.alignScriptedOpening(.init(degrees: 60, timestamp: 10.05))
    let expected = (FoldTuning.default.openingTrackEndAngle - 60)
        / (FoldTuning.default.openingTrackEndAngle - FoldTuning.default.sealAngle)
    #expect(aligned.phase == .unfolding)
    #expect(abs(aligned.progress - expected) < 1e-9)
    #expect(driver.tick(now: 10.06).progress <= expected)

    driver.trackScriptedOpening(.init(degrees: 70, timestamp: 10.2))
    #expect(driver.tick(now: 10.22).progress < expected)
}

@Test func alreadyOpenLidDoesNotFoldTheDesktopBackwards() {
    let driver = FoldDriver()
    driver.signalSleep()
    driver.beginScriptedUnfold(now: 10)

    let aligned = driver.alignScriptedOpening(.init(degrees: 100, timestamp: 10.05))
    #expect(aligned == .idle)
    #expect(driver.tick(now: 10.2) == .idle)
}

@Test func invalidInputAndDisplayTimesCannotInterruptOrPoisonAnUnfold() {
    let reference = FoldDriver()
    let noisy = FoldDriver()
    for driver in [reference, noisy] { driver.beginScriptedUnfold(now: 10) }
    noisy.ingest(.init(degrees: .nan, timestamp: 10.1))
    noisy.ingest(.init(degrees: 40, timestamp: .infinity))
    noisy.tick(now: .nan)
    noisy.tick(now: .infinity)
    #expect(noisy.tick(now: 10.31) == reference.tick(now: 10.31))
    #expect(noisy.tick(now: 10.7) == reference.tick(now: 10.7))
}

@Test func rejectedInputCannotChangeTheNextValidCloseFrame() {
    let reference = FoldDriver()
    let noisy = FoldDriver()
    for index in 0..<60 {
        let time = Double(index) / 60
        let sample = AngleSample(degrees: 120 - Double(index) * 1.5, timestamp: time)
        #expect(noisy.ingest(sample) == reference.ingest(sample))
        noisy.ingest(.init(degrees: 0, timestamp: time))
        noisy.ingest(.init(degrees: 0, timestamp: time - 1))
        noisy.ingest(.init(degrees: .nan, timestamp: time + 0.001))
        #expect(noisy.tick(now: time + 0.008) == reference.tick(now: time + 0.008))
    }
}

@Test func slowPhysicalOpeningHoldsRevealUntilLidIsOpen() {
    let driver = FoldDriver()
    driver.signalSleep()
    driver.beginScriptedUnfold(now: 100)

    driver.trackScriptedOpening(.init(degrees: 45, timestamp: 100.1))
    let halfway = driver.tick(now: 100.31)
    #expect(halfway.phase == .unfolding)
    #expect(halfway.progress > 0.5)

    let deadline = driver.tick(now: 100.621)
    #expect(deadline.phase == .unfolding)
    #expect(deadline.progress > 0.5)

    driver.trackScriptedOpening(.init(degrees: 70, timestamp: 100.8))
    let further = driver.tick(now: 100.8)
    #expect(further.progress < deadline.progress)
    #expect(further.progress > 0)

    for frame in 1...17 {
        driver.tick(now: 100.8 + Double(frame) / 60)
    }
    driver.trackScriptedOpening(.init(degrees: 100, timestamp: 101.1))
    #expect(driver.tick(now: 101.1).phase == .unfolding)
    #expect(driver.tick(now: 101.5).phase == .idle)
}

@Test func longOpeningAndPauseRemainLidDrivenBeyondOldTwoSecondTimeout() {
    let driver = FoldDriver()
    let tuning = FoldTuning.default
    driver.beginScriptedUnfold(now: 10)
    driver.alignScriptedOpening(.init(degrees: 35, timestamp: 10))
    var progressValues: [Double] = []
    for frame in 1...360 {
        let now = 10 + Double(frame) / 60
        // Pause at 35° for three seconds, then take three seconds to open.
        let angle = frame <= 180 ? 35 : 35 + Double(frame - 180) / 3
        driver.trackScriptedOpening(.init(degrees: angle.rounded(), timestamp: now))
        let state = driver.tick(now: now)
        progressValues.append(state.progress)
        if frame <= 180 {
            let expected = (tuning.openingTrackEndAngle - 35)
                / (tuning.openingTrackEndAngle - tuning.sealAngle)
            #expect(abs(state.progress - expected) < 0.0001)
            #expect(state.phase == .unfolding)
        }
    }
    #expect(zip(progressValues, progressValues.dropFirst()).allSatisfy { $1 <= $0 + 0.000001 })
    #expect(Set(progressValues.suffix(180)).count > 150)
    #expect(driver.tick(now: 16.5).phase == .idle)
}

@Test func wholeDegreeOpeningStepsAreSpreadAcrossDisplayFrames() {
    let driver = FoldDriver()
    let tuning = FoldTuning.default
    driver.beginScriptedUnfold(now: 0)
    driver.trackScriptedOpening(.init(degrees: 50, timestamp: 0.1))
    for frame in 0...12 {
        driver.tick(now: 0.8 + Double(frame) / 60)
    }
    let before = driver.state.progress

    driver.trackScriptedOpening(.init(degrees: 51, timestamp: 1.01))
    let first = driver.tick(now: 1.016).progress
    let second = driver.tick(now: 1.033).progress
    let rawStep = 1 / (tuning.openingTrackEndAngle - tuning.sealAngle)

    #expect(first < before)
    #expect(before - first < rawStep * 0.6)
    #expect(second < first, "progress continues between sensor readings")
    #expect(first >= (tuning.openingTrackEndAngle - 51)
        / (tuning.openingTrackEndAngle - tuning.sealAngle))
}

@Test func scriptedOpeningJitterCannotRefoldAndStaleSamplesAreIgnored() {
    let driver = FoldDriver()
    driver.beginScriptedUnfold(now: 20)
    driver.trackScriptedOpening(.init(degrees: 70, timestamp: 20.1))
    let first = driver.tick(now: 20.7)
    driver.trackScriptedOpening(.init(degrees: 60, timestamp: 20.8))
    driver.trackScriptedOpening(.init(degrees: 12, timestamp: 20.2))
    let second = driver.tick(now: 20.8)
    #expect(second.progress <= first.progress)
    #expect(second.phase == .unfolding)
}

@Test func stalledScriptedOpeningTimesOutSmoothly() {
    let driver = FoldDriver()
    let tuning = FoldTuning.default
    driver.beginScriptedUnfold(now: 10)
    driver.trackScriptedOpening(.init(degrees: 40, timestamp: 10.1))
    let held = driver.tick(now: 10 + tuning.openingTrackHoldSeconds)
    #expect(held.phase == .unfolding)
    #expect(held.progress > 0)
    let fading = driver.tick(now: 10 + tuning.openingTrackHoldSeconds + tuning.scriptedUnfoldSeconds / 2)
    #expect(fading.progress > 0)
    #expect(fading.progress < held.progress)
    #expect(driver.tick(now: 10.1 + tuning.openingTrackHoldSeconds + tuning.scriptedUnfoldSeconds).phase == .idle)
}

@Test func losingSensorReleasesScriptedOpeningConstraint() {
    let driver = FoldDriver()
    driver.beginScriptedUnfold(now: 10)
    driver.trackScriptedOpening(.init(degrees: 40, timestamp: 10.1))
    #expect(driver.tick(now: 10.621).phase == .unfolding)
    driver.clearScriptedOpeningTracking()
    let fading = driver.tick(now: 10.64)
    #expect(fading.phase == .unfolding)
    #expect(fading.progress > 0)
    #expect(driver.tick(now: 11.25).phase == .idle)
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
    _ = sweepTrackingPeak(driver, from: 50, to: 70, degreesPerSecond: 200, startingAt: t)
    #expect(driver.state.velocity < 0)      // unfolding: progress decreasing
}
