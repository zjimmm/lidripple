import Foundation
import Testing
import LidRippleCore
import LidRippleIntegration
@testable import LidRippleAppSupport

@Suite(.serialized)
@MainActor
struct AppCoordinatorTests {
    @Test func deniedLaunchStaysInertUntilExplicitPermissionActionSucceeds() {
        let harness = makeHarness(permissionGranted: false, requestResult: true)

        harness.coordinator.start(sessionAccess: .active)

        #expect(harness.onboarding.presentCount == 1)
        #expect(harness.permissionService.requestCount == 0)
        #expect(harness.input.startCount == 0)
        #expect(harness.lifecycle.enabledValues.last == false)
        #expect(harness.coordinator.menuController.snapshot.screenRecording == .notDetermined)

        harness.coordinator.screenRecordingAction()

        #expect(harness.permissionService.requestCount == 1)
        #expect(harness.input.startCount == 1)
        #expect(harness.lifecycle.enabledValues.last == true)
        #expect(harness.coordinator.menuController.snapshot.screenRecording == .granted)
    }

    @Test func inputSamplesAndModesReachTheSingleLifecycleAndAnimationClock() {
        let harness = makeHarness(permissionGranted: true, inputMode: .timedFallback)
        harness.lifecycle.ingestResult = FoldState(phase: .folding, progress: 0.2, velocity: 1)
        harness.coordinator.start(sessionAccess: .active)

        #expect(harness.input.startCount == 1)
        #expect(harness.lifecycle.inputAvailabilityValues.last == .timedFallback)
        #expect(harness.coordinator.menuController.snapshot.inputMode == "Sensor-less (experimental)")

        harness.input.emit(AngleSample(degrees: 70, timestamp: 1))
        #expect(harness.lifecycle.samples.count == 1)
        #expect(harness.animation.activeCount == 1)

        harness.lifecycle.tickResult = FoldState(phase: .idle, progress: 0, velocity: 0)
        harness.animation.fire()
        #expect(harness.lifecycle.tickCount == 1)
        #expect(harness.animation.activeCount == 0)
    }

    @Test func sleepHardSealsCaptureBeforeReturningEvenInFallbackMode() async {
        let harness = makeHarness(permissionGranted: true, inputMode: .timedFallback)
        harness.coordinator.start(sessionAccess: .active)
        harness.events.values.removeAll()

        harness.coordinator.systemWillSleep()

        #expect(!harness.events.values.contains("fallback-close"))
        #expect(harness.lifecycle.sleepCount == 1)
        #expect(harness.events.values.contains("hard-seal"))
        #expect(harness.input.stopCount == 1)
    }

    @Test func lockedLaunchWaitsForFreshUnfoldBeforeStartingInput() async {
        let harness = makeHarness(permissionGranted: true, inputMode: .sensor)
        harness.coordinator.start(sessionAccess: .restricted)
        #expect(harness.lifecycle.lockCount == 1)
        #expect(harness.input.startCount == 0)
        #expect(harness.onboarding.presentCount == 0)

        harness.events.values.removeAll()
        await harness.coordinator.screenDidUnlock(sessionAccess: .active, onConsole: true)

        let unfoldIndex = harness.events.values.firstIndex(of: "fresh-unfold")
        let inputIndex = harness.events.values.firstIndex(of: "input-start")
        #expect(unfoldIndex != nil)
        #expect(inputIndex != nil)
        if let unfoldIndex, let inputIndex { #expect(unfoldIndex < inputIndex) }
        #expect(harness.input.startCount == 1)
        #expect(!harness.input.sessionRestricted)
        #expect(harness.onboarding.presentCount == 0)
    }

    @Test func firstRunOnboardingWaitsForPositiveUnlock() async {
        let harness = makeHarness(permissionGranted: false)
        harness.coordinator.start(sessionAccess: .restricted)
        #expect(harness.onboarding.presentCount == 0)
        #expect(harness.permissionService.requestCount == 0)
        await harness.coordinator.screenDidUnlock(sessionAccess: .active, onConsole: true)
        #expect(harness.onboarding.presentCount == 1)
    }

    @Test func staleActiveStartupSnapshotDoesNotStartInputOrOnboarding() {
        let harness = makeHarness(permissionGranted: false)
        harness.sessionAccess.value = .restricted
        harness.coordinator.start(sessionAccess: .active)
        #expect(harness.input.startCount == 0)
        #expect(harness.onboarding.presentCount == 0)
        #expect(harness.input.sessionRestricted)
    }

    @Test func sessionChangeImmediatelyBeforeInputStartFailsClosed() {
        let harness = makeHarness(permissionGranted: true)
        // Startup's initial check, onboarding check, and post-onboarding
        // check all see active. The final input-enablement check does not.
        harness.sessionAccess.restrictOnRead = 4
        harness.coordinator.start(sessionAccess: .active)
        #expect(harness.input.startCount == 0)
        #expect(harness.input.sessionRestricted)
        #expect(harness.lifecycle.lockCount >= 1)
    }

    @Test func lateSessionRestrictionRejectsSamplesAndStopsAnimationClock() {
        let harness = makeHarness(permissionGranted: true)
        harness.lifecycle.ingestResult = FoldState(phase: .folding, progress: 0.2, velocity: 1)
        harness.coordinator.start(sessionAccess: .active)
        harness.input.emit(AngleSample(degrees: 70, timestamp: 1))
        #expect(harness.animation.activeCount == 1)

        harness.sessionAccess.value = .restricted
        harness.animation.fire()
        harness.input.emit(AngleSample(degrees: 60, timestamp: 2))
        #expect(harness.lifecycle.tickCount == 0)
        #expect(harness.lifecycle.samples.count == 1)
        #expect(harness.animation.activeCount == 0)
        #expect(harness.input.sessionRestricted)
    }

    @Test func missingLockKeyAtLaunchWaitsForInteractiveStatusMenu() async {
        let harness = makeHarness(permissionGranted: true)
        harness.sessionAccess.value = .unknown
        harness.coordinator.start(sessionAccess: .unknown)
        #expect(harness.input.startCount == 0)
        #expect(harness.input.sessionRestricted)

        harness.coordinator.menuDidOpen()
        for _ in 0..<100 where harness.input.startCount == 0 {
            await Task.yield()
        }
        #expect(harness.events.values.contains("fresh-unfold"))
        #expect(harness.input.startCount == 1)
    }

    @Test func statusMenuCannotUnlockAnOffConsoleSession() async {
        let harness = makeHarness(permissionGranted: true)
        harness.sessionAccess.value = .unknown
        harness.sessionAccess.onConsole = false
        harness.coordinator.start(sessionAccess: .unknown)
        harness.coordinator.menuDidOpen()
        await Task.yield()
        #expect(harness.input.startCount == 0)
        #expect(harness.input.sessionRestricted)
    }

    @Test func menuPresenceProofExpiresOnInterveningLock() async {
        let harness = makeHarness(permissionGranted: true)
        harness.sessionAccess.value = .unknown
        harness.coordinator.start(sessionAccess: .unknown)
        harness.coordinator.menuDidOpen()
        harness.coordinator.screenDidLock()
        await Task.yield()
        #expect(harness.lifecycle.unlockCount == 0)
        #expect(harness.input.startCount == 0)
        #expect(harness.input.sessionRestricted)
    }

    @Test func queuedUnlockNotificationExpiresOnInterveningLock() async {
        let harness = makeHarness(permissionGranted: true)
        harness.sessionAccess.value = .unknown
        harness.coordinator.start(sessionAccess: .unknown)
        let notificationGeneration = harness.coordinator.sessionEventGeneration
        harness.coordinator.screenDidLock()
        await harness.coordinator.screenDidUnlock(
            sessionAccess: .unknown,
            onConsole: true,
            notificationGeneration: notificationGeneration
        )
        #expect(harness.lifecycle.unlockCount == 0)
        #expect(harness.input.startCount == 0)
    }

    @Test func activationRefreshStartsRuntimeAfterSettingsGrant() {
        let harness = makeHarness(permissionGranted: false, requestResult: false)
        harness.preferences.screenRecordingRequestMade = true
        harness.coordinator.start(sessionAccess: .active)
        #expect(harness.input.startCount == 0)

        harness.permissionService.preflightResult = true
        harness.coordinator.applicationDidBecomeActive()

        #expect(harness.input.startCount == 1)
        #expect(harness.coordinator.menuController.snapshot.screenRecording == .granted)
    }

    @Test func wakeRetriesHIDFromAnActiveFallback() async {
        let harness = makeHarness(permissionGranted: true, inputMode: .timedFallback)
        harness.coordinator.start(sessionAccess: .active)

        await harness.coordinator.systemDidWake(sessionAccess: .active)

        #expect(harness.input.retryCount == 1)
        #expect(harness.input.startCount >= 1)
        #expect(harness.events.values.contains("fresh-unfold"))
    }

    @Test func debugSessionTearsDownThenRestoresPreferredRuntimeAndIntensity() async throws {
        let harness = makeHarness(permissionGranted: true, inputMode: .sensor)
        harness.coordinator.start(sessionAccess: .active)
        harness.events.values.removeAll()

        try await harness.coordinator.prepareDebugSession(intensity: 0.5)
        #expect(harness.events.values.prefix(3) == [
            "input-stop", "runtime-disabled", "capture-settled",
        ])
        #expect(harness.debugPresenter.beginTunings.last?.intensity == 0.5)
        #expect(harness.coordinator.isDebugging)

        harness.coordinator.setIntensity(0.75)
        #expect(harness.debugPresenter.tunings.last?.intensity == 0.75)
        await harness.coordinator.finishDebugSession()

        #expect(!harness.coordinator.isDebugging)
        #expect(harness.input.startCount == 2)
        #expect(harness.lifecycle.enabledValues.last == true)
    }

    @Test func lockSwitchAndSleepImmediatelyDismissDebugPreview() async throws {
        for restriction in 0..<3 {
            let harness = makeHarness(permissionGranted: true)
            harness.coordinator.start(sessionAccess: .active)
            try await harness.coordinator.prepareDebugSession(intensity: 1)
            switch restriction {
            case 0: harness.coordinator.screenDidLock()
            case 1: harness.coordinator.sessionResignedActive()
            default: harness.coordinator.systemWillSleep()
            }
            #expect(!harness.coordinator.isDebugging)
            #expect(harness.debugPresenter.endCount >= 1)
            #expect(harness.input.sessionRestricted)
            #expect(harness.input.startCount == 1)
        }
    }

    @Test func activationCannotBypassLockedSessionTruth() {
        let harness = makeHarness(permissionGranted: true)
        harness.coordinator.start(sessionAccess: .active)
        harness.coordinator.screenDidLock()
        harness.sessionAccess.value = .restricted
        harness.coordinator.sessionBecameActive(sessionAccess: .active)
        #expect(harness.input.sessionRestricted)
        #expect(harness.input.startCount == 1)
        #expect(harness.lifecycle.lockCount >= 2)
    }

    @Test func unlockAndWakeRejectStaleActiveNotification() async {
        let harness = makeHarness(permissionGranted: true)
        harness.coordinator.start(sessionAccess: .restricted)
        harness.sessionAccess.value = .restricted
        await harness.coordinator.screenDidUnlock(sessionAccess: .active, onConsole: true)
        await harness.coordinator.systemDidWake(sessionAccess: .active)
        #expect(harness.input.startCount == 0)
        #expect(harness.input.sessionRestricted)
    }

    @Test func explicitUnlockWorksWhenPrivateLockKeyIsMissingButConsoleIsKnown() async {
        let harness = makeHarness(permissionGranted: true)
        harness.coordinator.start(sessionAccess: .restricted)
        harness.sessionAccess.value = .unknown
        await harness.coordinator.screenDidUnlock(sessionAccess: .unknown, onConsole: true)
        #expect(harness.events.values.contains("fresh-unfold"))
        #expect(harness.input.startCount == 1)
    }

    @Test func explicitUnlockRejectsUnknownNonConsoleSession() async {
        let harness = makeHarness(permissionGranted: true)
        harness.coordinator.start(sessionAccess: .restricted)
        harness.sessionAccess.value = .unknown
        harness.sessionAccess.onConsole = false
        await harness.coordinator.screenDidUnlock(sessionAccess: .unknown, onConsole: false)
        #expect(!harness.events.values.contains("fresh-unfold"))
        #expect(harness.input.startCount == 0)
    }

    @Test func overlappingWakeAndUnlockShareOneFreshCapture() async {
        let harness = makeHarness(permissionGranted: true)
        harness.lifecycle.holdUnlock = true
        harness.coordinator.start(sessionAccess: .restricted)
        let wake = Task {
            await harness.coordinator.systemDidWake(sessionAccess: .active)
        }
        for _ in 0..<100 where !harness.lifecycle.isWaitingForUnlock {
            await Task.yield()
        }
        #expect(harness.lifecycle.isWaitingForUnlock)
        await harness.coordinator.screenDidUnlock(sessionAccess: .active, onConsole: true)
        #expect(harness.lifecycle.unlockCount == 1)
        harness.lifecycle.releaseUnlock()
        await wake.value
        #expect(harness.lifecycle.unlockCount == 1)
        #expect(harness.input.startCount == 1)
    }

    @Test func wakeArrivingDuringUnlockRetriesHIDAfterRuntimeRestores() async {
        let harness = makeHarness(permissionGranted: true, inputMode: .timedFallback)
        harness.lifecycle.holdUnlock = true
        harness.coordinator.start(sessionAccess: .restricted)
        let unlock = Task {
            await harness.coordinator.screenDidUnlock(sessionAccess: .active, onConsole: true)
        }
        for _ in 0..<100 where !harness.lifecycle.isWaitingForUnlock {
            await Task.yield()
        }
        #expect(harness.lifecycle.isWaitingForUnlock)
        await harness.coordinator.systemDidWake(sessionAccess: .active)
        #expect(harness.input.retryCount == 0)
        harness.lifecycle.releaseUnlock()
        await unlock.value
        #expect(harness.lifecycle.unlockCount == 1)
        #expect(harness.input.startCount == 1)
        #expect(harness.input.retryCount == 1)
    }

    @Test func wakeAfterInterveningSleepRetriesStaleUnlockCapture() async {
        let harness = makeHarness(permissionGranted: true)
        harness.lifecycle.holdUnlock = true
        harness.coordinator.start(sessionAccess: .restricted)
        let oldUnlock = Task {
            await harness.coordinator.screenDidUnlock(sessionAccess: .active, onConsole: true)
        }
        for _ in 0..<100 where !harness.lifecycle.isWaitingForUnlock {
            await Task.yield()
        }
        #expect(harness.lifecycle.isWaitingForUnlock)
        harness.coordinator.systemWillSleep()
        await harness.coordinator.systemDidWake(sessionAccess: .active)
        harness.lifecycle.holdUnlock = false
        harness.lifecycle.releaseUnlock()
        await oldUnlock.value
        for _ in 0..<100 where harness.lifecycle.unlockCount < 2 {
            await Task.yield()
        }
        #expect(harness.lifecycle.unlockCount == 2)
        #expect(harness.input.startCount == 1)
        #expect(!harness.input.sessionRestricted)
    }

    @Test func realUnlockAfterSleepRetriesOlderCaptureWithoutNewRestriction() async {
        let harness = makeHarness(permissionGranted: true)
        harness.lifecycle.holdUnlock = true
        harness.coordinator.start(sessionAccess: .restricted)
        let oldUnlock = Task {
            await harness.coordinator.screenDidUnlock(sessionAccess: .active, onConsole: true)
        }
        for _ in 0..<100 where !harness.lifecycle.isWaitingForUnlock {
            await Task.yield()
        }
        #expect(harness.lifecycle.isWaitingForUnlock)
        harness.coordinator.systemWillSleep()
        harness.sessionAccess.value = .unknown
        await harness.coordinator.screenDidUnlock(sessionAccess: .unknown, onConsole: true)
        harness.lifecycle.holdUnlock = false
        harness.lifecycle.releaseUnlock()
        await oldUnlock.value
        for _ in 0..<100 where harness.lifecycle.unlockCount < 2 {
            await Task.yield()
        }
        #expect(harness.lifecycle.unlockCount == 2)
        #expect(harness.input.startCount == 1)
    }

    @Test func rejectedOffConsoleUnlockInvalidatesEarlierPendingProof() async {
        let harness = makeHarness(permissionGranted: true)
        harness.lifecycle.holdUnlock = true
        harness.coordinator.start(sessionAccess: .restricted)
        let oldUnlock = Task {
            await harness.coordinator.screenDidUnlock(sessionAccess: .active, onConsole: true)
        }
        for _ in 0..<100 where !harness.lifecycle.isWaitingForUnlock {
            await Task.yield()
        }
        #expect(harness.lifecycle.isWaitingForUnlock)
        harness.coordinator.systemWillSleep()
        harness.sessionAccess.value = .unknown
        await harness.coordinator.screenDidUnlock(sessionAccess: .unknown, onConsole: true)
        harness.sessionAccess.onConsole = false
        await harness.coordinator.screenDidUnlock(sessionAccess: .unknown, onConsole: false)
        harness.sessionAccess.onConsole = true
        harness.lifecycle.holdUnlock = false
        harness.lifecycle.releaseUnlock()
        await oldUnlock.value
        for _ in 0..<100 { await Task.yield() }
        #expect(harness.lifecycle.unlockCount == 1)
        #expect(harness.input.startCount == 0)
        #expect(harness.input.sessionRestricted)
    }

    @Test func disabledPreferenceDoesNotEraseActiveDebugSource() async throws {
        let harness = makeHarness(permissionGranted: true)
        harness.coordinator.start(sessionAccess: .active)
        try await harness.coordinator.prepareDebugSession(intensity: 1)
        let disableCount = harness.lifecycle.enabledValues.count
        harness.coordinator.setEnabled(false)
        #expect(harness.coordinator.isDebugging)
        #expect(harness.debugPresenter.endCount == 0)
        #expect(harness.lifecycle.enabledValues.count == disableCount)
        await harness.coordinator.finishDebugSession()
        #expect(harness.lifecycle.enabledValues.last == false)
    }

    @Test func preferenceAndSessionRestrictionsPreserveProbedInputCapability() async {
        let harness = makeHarness(permissionGranted: true, inputMode: .timedFallback)
        harness.coordinator.start(sessionAccess: .active)
        harness.coordinator.setEnabled(false)
        #expect(harness.coordinator.inputMode == .timedFallback)
        #expect(harness.lifecycle.inputAvailabilityValues.last == .timedFallback)
        harness.coordinator.setEnabled(true)
        harness.coordinator.screenDidLock()
        #expect(harness.coordinator.inputMode == .timedFallback)
        #expect(harness.lifecycle.inputAvailabilityValues.last == .timedFallback)
        await harness.coordinator.screenDidUnlock(sessionAccess: .active, onConsole: true)
        #expect(harness.coordinator.inputMode == .timedFallback)
    }

    @Test func lockDuringPendingDebugPreparationCannotInstallOverlay() async {
        let harness = makeHarness(permissionGranted: true)
        harness.lifecycle.holdCaptureWait = true
        harness.coordinator.start(sessionAccess: .active)
        let preparation = Task {
            try await harness.coordinator.prepareDebugSession(intensity: 1)
        }
        for _ in 0..<100 where !harness.lifecycle.isWaitingForCapture {
            await Task.yield()
        }
        #expect(harness.lifecycle.isWaitingForCapture)
        harness.coordinator.screenDidLock()
        harness.lifecycle.releaseCaptureWait()
        do {
            try await preparation.value
            Issue.record("Cancelled debug preparation must not succeed")
        } catch is CancellationError {
            // Expected: it must not install a shielding overlay after lock.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(harness.debugPresenter.beginTunings.isEmpty)
        #expect(!harness.coordinator.isDebugging)
        #expect(harness.input.sessionRestricted)
    }

    private func makeHarness(
        permissionGranted: Bool,
        requestResult: Bool = false,
        inputMode: InputSourceMode = .sensor
    ) -> CoordinatorHarness {
        let events = CoordinatorEventLog()
        let sessionAccess = CoordinatorSessionAccess()
        let preferences = AppPreferences(storage: CoordinatorPreferencesStore())
        let permissionService = CoordinatorPermissionService(
            preflightResult: permissionGranted,
            requestResult: requestResult
        )
        let opener = CoordinatorURLOpener()
        let permission = ScreenRecordingPermissionController(
            service: permissionService,
            preferences: preferences,
            urlOpener: opener
        )
        let login = LaunchAtLoginController(
            service: CoordinatorLoginService(),
            preferences: preferences,
            urlOpener: opener
        )
        let onboarding = CoordinatorOnboardingPresenter(choice: .notNow)
        let lifecycle = CoordinatorLifecycle(events: events)
        let input = CoordinatorInput(mode: inputMode, events: events)
        let debugPresenter = CoordinatorDebugPresenter()
        let animation = CoordinatorAnimationScheduler()
        let coordinator = AppCoordinator(
            preferences: preferences,
            lifecycle: lifecycle,
            permission: permission,
            onboarding: onboarding,
            launchAtLogin: login,
            debugPresenter: debugPresenter,
            urlOpener: opener,
            inputFactory: { onSample, onModeChanged in
                input.onSample = onSample
                input.onModeChanged = onModeChanged
                return input
            },
            animationScheduler: animation,
            presentsMenu: false,
            presentsDebugPanel: false,
            now: { 42 },
            sessionAccessNow: { sessionAccess.current() },
            isCurrentConsoleNow: { sessionAccess.onConsole }
        )
        return CoordinatorHarness(
            coordinator: coordinator,
            preferences: preferences,
            lifecycle: lifecycle,
            input: input,
            permissionService: permissionService,
            onboarding: onboarding,
            debugPresenter: debugPresenter,
            animation: animation,
            events: events,
            sessionAccess: sessionAccess
        )
    }
}

@MainActor
private struct CoordinatorHarness {
    let coordinator: AppCoordinator
    let preferences: AppPreferences
    let lifecycle: CoordinatorLifecycle
    let input: CoordinatorInput
    let permissionService: CoordinatorPermissionService
    let onboarding: CoordinatorOnboardingPresenter
    let debugPresenter: CoordinatorDebugPresenter
    let animation: CoordinatorAnimationScheduler
    let events: CoordinatorEventLog
    let sessionAccess: CoordinatorSessionAccess
}

@MainActor
private final class CoordinatorSessionAccess {
    var value: ConsoleSessionAccess = .active
    var onConsole = true
    var restrictOnRead: Int?
    private var readCount = 0

    func current() -> ConsoleSessionAccess {
        readCount += 1
        if readCount == restrictOnRead { value = .restricted }
        return value
    }
}

@MainActor
private final class CoordinatorEventLog {
    var values: [String] = []
}

private final class CoordinatorPreferencesStore: AppPreferencesStoring {
    var values: [String: Any] = [:]
    func object(forKey defaultName: String) -> Any? { values[defaultName] }
    func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
}

private final class CoordinatorPermissionService: ScreenRecordingPermissionServicing,
    @unchecked Sendable
{
    var preflightResult: Bool
    var requestResult: Bool
    var requestCount = 0

    init(preflightResult: Bool, requestResult: Bool) {
        self.preflightResult = preflightResult
        self.requestResult = requestResult
    }

    func preflight() -> Bool { preflightResult }
    func request() -> Bool {
        requestCount += 1
        return requestResult
    }
}

@MainActor
private final class CoordinatorOnboardingPresenter: ScreenRecordingOnboardingPresenting {
    let choice: ScreenRecordingOnboardingChoice
    var presentCount = 0

    init(choice: ScreenRecordingOnboardingChoice) { self.choice = choice }
    func presentExplanation() -> ScreenRecordingOnboardingChoice {
        presentCount += 1
        return choice
    }
}

@MainActor
private final class CoordinatorURLOpener: ExternalURLOpening {
    var result = true
    var URLs: [URL] = []
    func open(_ url: URL) -> Bool {
        URLs.append(url)
        return result
    }
}

private struct CoordinatorLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginServiceStatus { .disabled }
    func register() throws {}
    func unregister() throws {}
}

@MainActor
private final class CoordinatorLifecycle: AppLifecycleControlling {
    let events: CoordinatorEventLog
    var state = FoldState(phase: .idle, progress: 0, velocity: 0)
    var ingestResult = FoldState(phase: .idle, progress: 0, velocity: 0)
    var tickResult = FoldState(phase: .idle, progress: 0, velocity: 0)
    var samples: [AngleSample] = []
    var enabledValues: [Bool] = []
    var tunings: [FoldTuning] = []
    var tickCount = 0
    var sleepCount = 0
    var lockCount = 0
    var sensorRecoveredCount = 0
    var sensorUnavailableCount = 0
    var inputAvailabilityValues: [FoldInputAvailability] = []
    var holdCaptureWait = false
    var holdUnlock = false
    var unlockCount = 0
    private var unlockWait: CheckedContinuation<Void, Never>?
    var isWaitingForUnlock: Bool { unlockWait != nil }
    private var captureWait: CheckedContinuation<Void, Never>?
    var isWaitingForCapture: Bool { captureWait != nil }

    init(events: CoordinatorEventLog) { self.events = events }

    func ingest(_ sample: AngleSample) -> FoldState {
        samples.append(sample)
        state = ingestResult
        return state
    }
    func tick(now: TimeInterval) -> FoldState {
        tickCount += 1
        state = tickResult
        return state
    }
    func systemWillSleep() -> FoldState {
        sleepCount += 1
        events.values.append("hard-seal")
        state = FoldState(phase: .sealed, progress: 1, velocity: 0)
        return state
    }
    func sessionLocked() -> FoldState {
        lockCount += 1
        state = FoldState(phase: .sealed, progress: 1, velocity: 0)
        return state
    }
    func sessionUnlocked(
        firstFrameTimeout: TimeInterval,
        now: @MainActor () -> TimeInterval
    ) async -> FoldState {
        unlockCount += 1
        events.values.append("fresh-unfold")
        if holdUnlock {
            await withCheckedContinuation { continuation in unlockWait = continuation }
        }
        state = FoldState(phase: .unfolding, progress: 1, velocity: -1)
        return state
    }
    func releaseUnlock() {
        unlockWait?.resume()
        unlockWait = nil
    }
    func sessionResignedActive() -> FoldState { state }
    func sessionBecameActive() -> FoldState { state }
    func displayConfigurationChanged() -> FoldState { state }
    func sensorUnavailable() -> FoldState {
        sensorUnavailableCount += 1
        return state
    }
    func sensorRecovered() -> FoldState {
        sensorRecoveredCount += 1
        return state
    }
    func setInputAvailability(_ availability: FoldInputAvailability) -> FoldState {
        inputAvailabilityValues.append(availability)
        return state
    }
    func setEnabled(_ enabled: Bool) -> FoldState {
        enabledValues.append(enabled)
        events.values.append(enabled ? "runtime-enabled" : "runtime-disabled")
        return state
    }
    func setReducedQuality(_ reduced: Bool) {}
    func setTuning(_ tuning: FoldTuning) { tunings.append(tuning) }
    func waitForPendingCapture() async {
        if holdCaptureWait {
            await withCheckedContinuation { continuation in captureWait = continuation }
        }
        events.values.append("capture-settled")
    }
    func releaseCaptureWait() {
        captureWait?.resume()
        captureWait = nil
    }
    func shutdown() async { events.values.append("shutdown") }
}

@MainActor
private final class CoordinatorInput: AppInputSourceControlling {
    var mode: InputSourceMode
    var isEnabled = false
    var sessionRestricted = false
    var startCount = 0
    var stopCount = 0
    var fallbackCloseCount = 0
    var retryCount = 0
    var onSample: InputSourceController.SampleHandler?
    var onModeChanged: InputSourceController.ModeHandler?
    let events: CoordinatorEventLog

    init(mode: InputSourceMode, events: CoordinatorEventLog) {
        self.mode = mode
        self.events = events
    }

    func start() -> InputSourceMode {
        isEnabled = true
        startCount += 1
        events.values.append("input-start")
        onModeChanged?(mode)
        return mode
    }
    func setEnabled(_ enabled: Bool) -> InputSourceMode {
        if enabled { return start() }
        stop()
        return mode
    }
    func stop() {
        guard isEnabled else { return }
        isEnabled = false
        stopCount += 1
        events.values.append("input-stop")
    }
    func setSessionRestricted(_ restricted: Bool) { sessionRestricted = restricted }
    func beginFallbackClose() -> Bool {
        guard isEnabled, !sessionRestricted, mode == .timedFallback else { return false }
        fallbackCloseCount += 1
        events.values.append("fallback-close")
        return true
    }
    func cancelFallbackTransition() {}
    func retryHID() { retryCount += 1 }
    func waitForRecovery() async {}
    func emit(_ sample: AngleSample) { onSample?(sample) }
}

@MainActor
private final class CoordinatorDebugPresenter: AppDebugPresenting {
    var beginTunings: [FoldTuning] = []
    var tunings: [FoldTuning] = []
    var endCount = 0
    func beginDebugPreview(tuning: FoldTuning) throws { beginTunings.append(tuning) }
    func updateDebugPreview(progress: Double, direction: Double) {}
    func endDebugPreview() { endCount += 1 }
    func setTuning(_ tuning: FoldTuning) { tunings.append(tuning) }
}

@MainActor
private final class CoordinatorAnimationScheduler: AppAnimationScheduling {
    private final class Token: AppAnimationCancellation {
        weak var owner: CoordinatorAnimationScheduler?
        func cancel() { owner?.action = nil }
    }

    var action: (@MainActor () -> Void)?
    var activeCount: Int { action == nil ? 0 : 1 }
    func schedule(
        interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any AppAnimationCancellation {
        self.action = action
        let token = Token()
        token.owner = self
        return token
    }
    func fire() { action?() }
}
