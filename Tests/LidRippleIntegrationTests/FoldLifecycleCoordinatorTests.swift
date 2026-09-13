import CoreGraphics
import CoreVideo
import Metal
import Testing
import LidRippleCapture
import LidRippleCore
import LidRippleTrace
@testable import LidRippleIntegration

@Suite(.serialized)
@MainActor
struct FoldLifecycleCoordinatorTests {
    @Test func closeWarmFreezeReverseAndReenterUseOneCycleAtATime() async throws {
        let frame = try makeFrame()
        let capture = FakeCapture(frame: frame)
        let output = FakeOutput()
        let coordinator = makeCoordinator(capture: capture, output: output)

        driveToArmed(coordinator, startingAt: 0)
        await coordinator.waitForPendingCapture()
        #expect(await capture.warmCount == 1)
        #expect(output.states.isEmpty)

        coordinator.ingest(.init(degrees: 60, timestamp: 0.2))
        await coordinator.waitForPendingCapture()
        #expect(await capture.freezeCount == 1)
        #expect(output.sourceCount == 1)
        #expect(output.states.last?.phase == .folding)
        #expect(await capture.lastDisplayID == 7)
        #expect(await capture.lastWindowID == 42)

        coordinator.ingest(.init(degrees: 100, timestamp: 0.3))
        #expect(coordinator.state.phase == .unfolding)
        coordinator.tick(now: 0.31)
        #expect(output.states.last?.phase == .unfolding)

        var timestamp = 0.3
        while coordinator.state.phase != .idle, timestamp < 3 {
            timestamp += 1.0 / 60.0
            coordinator.ingest(.init(degrees: 100, timestamp: timestamp))
        }
        #expect(coordinator.state.phase == .idle)
        await coordinator.waitForPendingCapture()
        #expect(output.clearCount >= 2)

        driveToArmed(coordinator, startingAt: timestamp + 0.1)
        await coordinator.waitForPendingCapture()
        coordinator.ingest(.init(degrees: 60, timestamp: timestamp + 0.3))
        await coordinator.waitForPendingCapture()
        #expect(await capture.warmCount == 2)
        #expect(await capture.freezeCount == 2)
        #expect(output.sourceCount == 2)
    }

    @Test func sleepSealsAndImmediatelyTearsDownCapture() async throws {
        let capture = FakeCapture(frame: try makeFrame())
        let output = FakeOutput()
        let coordinator = makeCoordinator(capture: capture, output: output)

        driveToArmed(coordinator, startingAt: 0)
        await coordinator.waitForPendingCapture()
        let state = coordinator.systemWillSleep()
        await coordinator.waitForPendingCapture()

        #expect(state.phase == .sealed)
        #expect(coordinator.state.progress == 1)
        #expect(await capture.resetCount >= 2)
    }

    @Test func lockHidesContentAndUnlockUsesAFreshFrame() async throws {
        let capture = FakeCapture(frame: try makeFrame())
        let output = FakeOutput()
        let coordinator = makeCoordinator(capture: capture, output: output)

        driveToArmed(coordinator, startingAt: 0)
        await coordinator.waitForPendingCapture()
        coordinator.ingest(.init(degrees: 60, timestamp: 0.2))
        await coordinator.waitForPendingCapture()
        #expect(output.sourceCount == 1)

        coordinator.sessionLocked()
        await coordinator.waitForPendingCapture()
        #expect(coordinator.availability == .locked)
        #expect(output.hideCount >= 1)
        #expect(output.clearCount >= 1)

        let unlocked = await coordinator.sessionUnlocked(now: { 5 })
        #expect(unlocked.phase == .unfolding)
        #expect(unlocked.progress == 1)
        #expect(output.sourceCount == 2)
        #expect(!coordinator.usesFallbackReveal)
        #expect(await capture.freezeCount == 2)

        let finished = coordinator.tick(now: 5.621)
        await coordinator.waitForPendingCapture()
        #expect(finished.phase == .idle)
        #expect(output.states.last?.phase == .idle)
    }

    @Test func unlockCaptureFailureUsesDarkFallbackAndNeverStaleSource() async throws {
        let capture = FakeCapture(frame: try makeFrame(), warmError: TestError.denied)
        let output = FakeOutput()
        let coordinator = makeCoordinator(capture: capture, output: output)

        coordinator.sessionLocked()
        let state = await coordinator.sessionUnlocked(now: { 10 })

        #expect(state.phase == .unfolding)
        #expect(coordinator.usesFallbackReveal)
        #expect(coordinator.lastCaptureErrorDescription != nil)
        #expect(output.sourceCount == 0)
        #expect(output.fallbackCount == 1)
        #expect(output.states.last?.progress == 1)
    }

    @Test func freshUnlockWaitsForFirstSensorPoseBeforeShowingFold() async throws {
        let capture = FakeCapture(frame: try makeFrame())
        let output = FakeOutput()
        let coordinator = makeCoordinator(capture: capture, output: output)

        coordinator.sessionLocked()
        #expect(await coordinator.sessionUnlocked(now: { 10 }).phase == .unfolding)
        #expect(output.sourceCount == 1)
        #expect(!coordinator.overlayVisible)

        _ = coordinator.tick(now: 10.05)
        #expect(!coordinator.overlayVisible)
        let aligned = coordinator.ingest(.init(degrees: 60, timestamp: 10.06))
        #expect(aligned.phase == .unfolding)
        #expect(aligned.progress < 0.5)
        #expect(coordinator.overlayVisible)
        #expect(output.states.last?.progress == aligned.progress)
    }

    @Test func alreadyOpenFirstReadingSkipsLatePostUnlockFold() async throws {
        let capture = FakeCapture(frame: try makeFrame())
        let output = FakeOutput()
        let coordinator = makeCoordinator(capture: capture, output: output)

        coordinator.sessionLocked()
        _ = await coordinator.sessionUnlocked(now: { 20 })
        let state = coordinator.ingest(.init(degrees: 100, timestamp: 20.02))
        await coordinator.waitForPendingCapture()
        #expect(state.phase == .idle)
        #expect(!coordinator.overlayVisible)
        #expect(!coordinator.diagnostics.requiresScriptedUnfold)
        #expect(output.sourceCount == 1)
    }

    @Test func missingFirstSensorReadingDoesNotLeaveUnlockHiddenForever() async throws {
        let capture = FakeCapture(frame: try makeFrame())
        let output = FakeOutput()
        let coordinator = makeCoordinator(capture: capture, output: output)

        coordinator.sessionLocked()
        _ = await coordinator.sessionUnlocked(now: { 30 })
        #expect(!coordinator.overlayVisible)
        _ = coordinator.tick(now: 30.13)
        #expect(coordinator.overlayVisible)
        #expect(output.states.last?.phase == .unfolding)
    }

    @Test func unlockWithoutBuiltInDisplayStillResetsAnyCapture() async throws {
        let capture = FakeCapture(frame: try makeFrame())
        let output = FakeOutput()
        let coordinator = FoldLifecycleCoordinator(
            driver: FoldDriver(),
            capture: capture,
            output: output,
            displayID: { nil }
        )

        coordinator.sessionLocked()
        await coordinator.waitForPendingCapture()
        let resetsBeforeUnlock = await capture.resetCount
        let state = await coordinator.sessionUnlocked(now: { 12 })

        #expect(state.phase == .sealed)
        #expect(coordinator.availability == .displayUnavailable)
        #expect(await capture.resetCount == resetsBeforeUnlock + 1)
        #expect(output.sourceCount == 0)
        #expect(output.fallbackCount == 0)
    }

    @Test func lockDuringScriptedUnfoldSnapsSealedAndCancelsReveal() async throws {
        let capture = FakeCapture(frame: try makeFrame())
        let output = FakeOutput()
        let coordinator = makeCoordinator(capture: capture, output: output)

        coordinator.sessionLocked()
        _ = await coordinator.sessionUnlocked(now: { 20 })
        #expect(coordinator.state.phase == .unfolding)

        let locked = coordinator.sessionLocked()
        await coordinator.waitForPendingCapture()
        #expect(locked.phase == .sealed)
        #expect(coordinator.tick(now: 21).phase == .sealed)
        #expect(output.hideCount >= 2)
    }

    @Test func timedFallbackUnfoldSuppressesInputUntilFullDurationThenAcceptsNextClose() async throws {
        let capture = FakeCapture(frame: try makeFrame())
        let output = FakeOutput()
        let coordinator = makeCoordinator(capture: capture, output: output)
        coordinator.setInputAvailability(.timedFallback)

        coordinator.sessionLocked()
        let unlocked = await coordinator.sessionUnlocked(now: {
            #expect(output.sourceCount == 1)
            return 30
        })
        #expect(unlocked.phase == .unfolding)

        coordinator.ingest(.init(degrees: 40, timestamp: 30.2))
        #expect(coordinator.state == unlocked)
        #expect(coordinator.diagnostics.requiresScriptedUnfold)

        #expect(coordinator.tick(now: 30.621).phase == .idle)
        await coordinator.waitForPendingCapture()
        #expect(!coordinator.diagnostics.requiresScriptedUnfold)

        driveToArmed(coordinator, startingAt: 31)
        await coordinator.waitForPendingCapture()
        #expect(coordinator.state.phase == .armed)
    }

    @Test func sensorUnfoldWaitsForPhysicalOpeningThenAcceptsNextClose() async throws {
        let capture = FakeCapture(frame: try makeFrame())
        let output = FakeOutput()
        let coordinator = makeCoordinator(capture: capture, output: output)

        coordinator.sessionLocked()
        #expect(await coordinator.sessionUnlocked(now: { 30 }).phase == .unfolding)
        coordinator.ingest(.init(degrees: 40, timestamp: 30.2))
        let held = coordinator.tick(now: 30.621)
        #expect(held.phase == .unfolding)
        #expect(held.progress > 0.5)
        #expect(coordinator.diagnostics.requiresScriptedUnfold)

        coordinator.ingest(.init(degrees: 100, timestamp: 30.9))
        #expect(coordinator.tick(now: 30.9).phase == .unfolding)
        #expect(coordinator.tick(now: 31.3).phase == .idle)
        #expect(!coordinator.diagnostics.requiresScriptedUnfold)

        driveToArmed(coordinator, startingAt: 31.4)
        await coordinator.waitForPendingCapture()
        #expect(coordinator.state.phase == .armed)
    }

    @Test func physicalSealReopensWithSameFrozenFrame() async throws {
        let capture = FakeCapture(frame: try makeFrame())
        let output = FakeOutput()
        let coordinator = makeCoordinator(capture: capture, output: output)

        driveToArmed(coordinator, startingAt: 0)
        await coordinator.waitForPendingCapture()
        coordinator.ingest(.init(degrees: 60, timestamp: 0.2))
        await coordinator.waitForPendingCapture()
        coordinator.ingest(.init(degrees: 0, timestamp: 0.3))
        #expect(coordinator.state.phase == .sealed)

        coordinator.ingest(.init(degrees: 40, timestamp: 0.4))
        #expect(coordinator.state.phase == .unfolding)
        coordinator.tick(now: 0.41)
        #expect(output.sourceCount == 1)
        #expect(await capture.freezeCount == 1)
        #expect(output.states.last?.phase == .unfolding)
    }

    @Test func displayChangeAbortsActiveFoldAndRetargetsOrDisables() async throws {
        let capture = FakeCapture(frame: try makeFrame())
        let output = FakeOutput()
        let coordinator = makeCoordinator(capture: capture, output: output)

        driveToArmed(coordinator, startingAt: 0)
        await coordinator.waitForPendingCapture()
        coordinator.ingest(.init(degrees: 60, timestamp: 0.2))
        await coordinator.waitForPendingCapture()

        #expect(coordinator.displayConfigurationChanged().phase == .folding)
        #expect(coordinator.availability == .active)
        #expect(output.reconfigureCount == 1)

        output.canReconfigure = false
        #expect(coordinator.displayConfigurationChanged().phase == .sealed)
        #expect(coordinator.availability == .displayUnavailable)
        #expect(output.states.contains { $0.phase == .sealed })
    }

    @Test func displayIdentityChangeSealsThenRecoversAndNilReturnRecoversOnOneEvent() async throws {
        let capture = FakeCapture(frame: try makeFrame())
        let output = FakeOutput()
        let currentDisplay = DisplayBox(7)
        var tuning = FoldTuning.default
        tuning.filterCutoffHz = 1_000
        tuning.velocitySmoothingHz = 1_000
        tuning.deadbandDegrees = 0
        tuning.directionHoldSeconds = 0
        tuning.directionMinTravelDegrees = 0
        let coordinator = FoldLifecycleCoordinator(
            driver: FoldDriver(tuning: tuning),
            capture: capture,
            output: output,
            displayID: { currentDisplay.value }
        )

        driveToArmed(coordinator, startingAt: 0)
        await coordinator.waitForPendingCapture()
        coordinator.ingest(.init(degrees: 60, timestamp: 0.2))
        await coordinator.waitForPendingCapture()

        currentDisplay.value = 8
        #expect(coordinator.displayConfigurationChanged().phase == .idle)
        #expect(coordinator.availability == .active)
        #expect(output.states.contains { $0.phase == .sealed })

        currentDisplay.value = nil
        #expect(coordinator.displayConfigurationChanged().phase == .idle)
        #expect(coordinator.availability == .displayUnavailable)

        currentDisplay.value = 8
        #expect(coordinator.displayConfigurationChanged().phase == .idle)
        #expect(coordinator.availability == .active)
    }

    @Test func fastUserSwitchAndSensorLossBailToIdle() async throws {
        let capture = FakeCapture(frame: try makeFrame())
        let output = FakeOutput()
        let coordinator = makeCoordinator(capture: capture, output: output)

        driveToArmed(coordinator, startingAt: 0)
        #expect(coordinator.sessionResignedActive().phase == .idle)
        await coordinator.waitForPendingCapture()
        #expect(coordinator.availability == .sessionInactive)
        #expect(coordinator.sessionBecameActive().phase == .idle)
        #expect(coordinator.availability == .active)

        #expect(coordinator.sensorUnavailable().phase == .idle)
        await coordinator.waitForPendingCapture()
        #expect(coordinator.availability == .inputUnavailable)
        #expect(coordinator.sensorRecovered().phase == .idle)
        #expect(coordinator.availability == .active)
        #expect(coordinator.setInputAvailability(.timedFallback).phase == .idle)
        #expect(coordinator.availability == .active)
        #expect(coordinator.diagnostics.inputAvailability == .timedFallback)
    }

    @Test func sensorAndDisplayRecoveryCannotOverrideLockAuthority() async throws {
        let capture = FakeCapture(frame: try makeFrame())
        let output = FakeOutput()
        let display = DisplayBox(7)
        let coordinator = FoldLifecycleCoordinator(
            capture: capture,
            output: output,
            displayID: { display.value }
        )

        coordinator.sessionLocked()
        coordinator.sensorUnavailable()
        #expect(coordinator.availability == .locked)
        #expect(coordinator.diagnostics.inputAvailability == .unavailable)
        #expect(coordinator.diagnostics.sessionRestricted)

        display.value = nil
        coordinator.displayConfigurationChanged()
        #expect(coordinator.availability == .locked)
        display.value = 7
        coordinator.displayConfigurationChanged()
        #expect(coordinator.availability == .locked)
        #expect(coordinator.diagnostics.builtInDisplayAvailable)

        coordinator.ingest(.init(degrees: 50, timestamp: 1))
        #expect(coordinator.state.phase == .sealed)

        let unlocked = await coordinator.sessionUnlocked(now: { 2 })
        #expect(unlocked.phase == .unfolding)
        #expect(coordinator.availability == .inputUnavailable)
        #expect(output.sourceCount == 1)
    }

    @Test func displayEventsCannotResurrectDisabledOrInactiveRuntime() async throws {
        let capture = FakeCapture(frame: try makeFrame())
        let output = FakeOutput()
        let display = DisplayBox(7)
        let disabled = FoldLifecycleCoordinator(
            capture: capture,
            output: output,
            displayID: { display.value }
        )

        disabled.setEnabled(false)
        display.value = 8
        disabled.displayConfigurationChanged()
        #expect(disabled.availability == .disabled)

        let inactive = FoldLifecycleCoordinator(
            capture: capture,
            output: output,
            displayID: { display.value }
        )
        inactive.sessionResignedActive()
        display.value = 9
        inactive.displayConfigurationChanged()
        #expect(inactive.availability == .sessionInactive)
    }

    @Test func unlockResolvesAReturnedDisplayEvenWhenScreenChangeNotificationWasMissed() async throws {
        let capture = FakeCapture(frame: try makeFrame())
        let output = FakeOutput()
        let display = DisplayBox(7)
        let coordinator = FoldLifecycleCoordinator(
            capture: capture,
            output: output,
            displayID: { display.value }
        )

        coordinator.sessionLocked()
        display.value = nil
        coordinator.displayConfigurationChanged()
        #expect(coordinator.availability == .locked)
        #expect(!coordinator.diagnostics.builtInDisplayAvailable)

        // The panel comes back but no didChangeScreenParameters notification
        // arrives before the explicit unlock notification.
        display.value = 7
        let unlocked = await coordinator.sessionUnlocked(now: { 50 })
        #expect(unlocked.phase == .unfolding)
        #expect(coordinator.diagnostics.builtInDisplayAvailable)
        #expect(output.reconfigureCount >= 1)
        #expect(coordinator.tick(now: 50.621).phase == .idle)
    }

    @Test func qualityModeIsForwardedWithoutChangingDriverState() async throws {
        let capture = FakeCapture(frame: try makeFrame())
        let output = FakeOutput()
        let coordinator = makeCoordinator(capture: capture, output: output)

        coordinator.setReducedQuality(true)
        coordinator.setReducedQuality(false)

        #expect(output.qualityModes == [true, false])
        #expect(coordinator.state == .idle)
    }

    @Test func lateWarmCompletionCannotFreezeOrShowAfterLock() async throws {
        let gate = AsyncGate()
        let capture = FakeCapture(frame: try makeFrame(), warmGate: gate)
        let output = FakeOutput()
        let coordinator = makeCoordinator(capture: capture, output: output)

        driveToArmed(coordinator, startingAt: 0)
        await gate.waitUntilEntered()
        coordinator.ingest(.init(degrees: 60, timestamp: 0.2))
        coordinator.sessionLocked()
        await gate.release()
        for _ in 0..<10 { await Task.yield() }
        await coordinator.waitForPendingCapture()

        #expect(coordinator.availability == .locked)
        #expect(await capture.freezeCount == 0)
        #expect(output.sourceCount == 0)
        #expect(!coordinator.diagnostics.overlayVisible)
    }

    @Test func disableInvalidatesUnlockCaptureBeforeItCanReveal() async throws {
        let gate = AsyncGate()
        let capture = FakeCapture(frame: try makeFrame(), warmGate: gate)
        let output = FakeOutput()
        let coordinator = makeCoordinator(capture: capture, output: output)
        coordinator.sessionLocked()

        let unlockTask = Task { @MainActor in
            await coordinator.sessionUnlocked(now: { 40 })
        }
        await gate.waitUntilEntered()
        coordinator.setEnabled(false)
        await gate.release()
        _ = await unlockTask.value
        await coordinator.waitForPendingCapture()

        #expect(coordinator.availability == .disabled)
        #expect(coordinator.state.phase == .idle)
        #expect(await capture.freezeCount == 0)
        #expect(output.sourceCount == 0)
        #expect(!coordinator.diagnostics.requiresScriptedUnfold)
    }

    @Test func allCanonicalTracesDriveTheIntegratedCaptureAndOutputWithoutOrphans() async throws {
        for trace in TraceGenerator.all {
            let capture = FakeCapture(frame: try makeFrame())
            let output = FakeOutput()
            let coordinator = FoldLifecycleCoordinator(
                capture: capture,
                output: output,
                displayID: { 7 }
            )
            let expectedDriver = FoldDriver()

            for sample in trace.angleSamples {
                let expected = expectedDriver.ingest(sample)
                let actual = coordinator.ingest(sample)
                #expect(actual == expected, "\(trace.name) diverged from FoldDriver")
                await coordinator.waitForPendingCapture()
            }
            await coordinator.waitForPendingCapture()

            #expect(coordinator.state.phase == expectedDriver.state.phase, "\(trace.name) terminal phase")
            #expect(await capture.freezeCount <= capture.warmCount)
            #expect(await capture.warmCount <= 2, "\(trace.name) opened extra capture cycles")
            if coordinator.state.phase == .idle {
                #expect(!coordinator.diagnostics.overlayVisible)
                #expect(coordinator.diagnostics.captureActivity == .idle)
            }
        }
    }

    private func makeCoordinator(
        capture: FakeCapture,
        output: FakeOutput
    ) -> FoldLifecycleCoordinator {
        var tuning = FoldTuning.default
        tuning.filterCutoffHz = 1_000
        tuning.velocitySmoothingHz = 1_000
        tuning.deadbandDegrees = 0
        tuning.directionHoldSeconds = 0
        tuning.directionMinTravelDegrees = 0
        return FoldLifecycleCoordinator(
            driver: FoldDriver(tuning: tuning),
            capture: capture,
            output: output,
            displayID: { 7 }
        )
    }

    private func driveToArmed(
        _ coordinator: FoldLifecycleCoordinator,
        startingAt timestamp: TimeInterval
    ) {
        coordinator.ingest(.init(degrees: 120, timestamp: timestamp))
        coordinator.ingest(.init(degrees: 100, timestamp: timestamp + 0.1))
        #expect(coordinator.state.phase == .armed)
    }
}

private enum TestError: Error { case denied }

@MainActor
private final class DisplayBox {
    var value: CGDirectDisplayID?
    init(_ value: CGDirectDisplayID?) { self.value = value }
}

private actor FakeCapture: FoldCapturing {
    private(set) var warmCount = 0
    private(set) var freezeCount = 0
    private(set) var resetCount = 0
    private(set) var lastDisplayID: CGDirectDisplayID?
    private(set) var lastWindowID: CGWindowID?

    let frame: CapturedFrame
    let warmError: TestError?
    let warmGate: AsyncGate?

    init(
        frame: CapturedFrame,
        warmError: TestError? = nil,
        warmGate: AsyncGate? = nil
    ) {
        self.frame = frame
        self.warmError = warmError
        self.warmGate = warmGate
    }

    func warm(
        displayID: CGDirectDisplayID,
        excludingWindowID: CGWindowID
    ) async throws {
        warmCount += 1
        lastDisplayID = displayID
        lastWindowID = excludingWindowID
        if let warmGate { await warmGate.enterAndWait() }
        if let warmError { throw warmError }
    }

    func freeze(waitingUpTo timeout: TimeInterval) async throws -> CapturedFrame {
        freezeCount += 1
        return frame
    }

    func reset() async { resetCount += 1 }
}

private actor AsyncGate {
    private var entered = false
    private var isOpen = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func enterAndWait() async {
        entered = true
        let enteredWaiters = entryWaiters
        entryWaiters.removeAll()
        for waiter in enteredWaiters { waiter.resume() }
        guard !isOpen else { return }
        await withCheckedContinuation { openWaiters.append($0) }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() {
        isOpen = true
        let waiters = openWaiters
        openWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}

@MainActor
private final class FakeOutput: FoldLifecycleOutput {
    let captureExclusionWindowID: CGWindowID = 42
    var sourceCount = 0
    var fallbackCount = 0
    var clearCount = 0
    var hideCount = 0
    var reconfigureCount = 0
    var canReconfigure = true
    var states: [FoldState] = []
    var qualityModes: [Bool] = []

    func setSource(_ frame: CapturedFrame) throws { sourceCount += 1 }
    func setFallbackSource() throws { fallbackCount += 1 }
    func clearSource() { clearCount += 1 }
    func update(_ state: FoldState) { states.append(state) }
    func hide() { hideCount += 1 }
    func setReducedQuality(_ reduced: Bool) { qualityModes.append(reduced) }
    func reconfigureForBuiltInDisplay() -> Bool {
        reconfigureCount += 1
        return canReconfigure
    }
}

private func makeFrame() throws -> CapturedFrame {
    let device = try #require(MTLCreateSystemDefaultDevice())
    var cache: CVMetalTextureCache?
    let cacheStatus = CVMetalTextureCacheCreate(
        kCFAllocatorDefault,
        nil,
        device,
        nil,
        &cache
    )
    #expect(cacheStatus == kCVReturnSuccess)
    let attributes: [CFString: Any] = [
        kCVPixelBufferMetalCompatibilityKey: true,
        kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
    ]
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        4,
        4,
        kCVPixelFormatType_32BGRA,
        attributes as CFDictionary,
        &pixelBuffer
    )
    #expect(status == kCVReturnSuccess)
    return try CapturedFrame.make(
        pixelBuffer: try #require(pixelBuffer),
        textureCache: try #require(cache)
    )
}
