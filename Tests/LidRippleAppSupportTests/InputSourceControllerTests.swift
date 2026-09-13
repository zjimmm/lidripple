import Foundation
import Testing
import LidRippleCore
import LidRippleIntegration
@testable import LidRippleAppSupport

@Suite(.serialized)
@MainActor
struct InputSourceControllerTests {
    @Test func launchPrefersAvailableHIDAndDoesNotConstructFallback() async {
        let hid = FakeAngleSource()
        var fallbackCreations = 0
        let recorder = Recorder()
        let controller = makeController(
            hidSources: [hid],
            fallbackFactory: {
                fallbackCreations += 1
                return FakeFallbackSource()
            },
            recorder: recorder
        )

        #expect(controller.start() == .sensor)
        #expect(controller.mode == .sensor)
        #expect(hid.startCount == 1)
        #expect(fallbackCreations == 0)

        hid.emit(.init(degrees: 91, timestamp: 1))
        await settle()
        #expect(recorder.samples.map(\.degrees) == [91])
        #expect(recorder.modes == [.sensor])
    }

    @Test func absentHIDSelectsFallbackAtLaunch() {
        let hid = FakeAngleSource(isAvailable: false)
        let fallback = FakeFallbackSource()
        let controller = makeController(hidSources: [hid], fallbackSources: [fallback])

        #expect(controller.start() == .timedFallback)
        #expect(hid.startCount == 0)
        #expect(hid.stopCount >= 1)
        #expect(fallback.startCount == 1)
    }

    @Test func HIDStartFailureSelectsFallbackAtLaunch() {
        let hid = FakeAngleSource(startError: TestError.startFailed)
        let fallback = FakeFallbackSource()
        let controller = makeController(hidSources: [hid], fallbackSources: [fallback])

        #expect(controller.start() == .timedFallback)
        #expect(hid.startCount == 1)
        #expect(hid.stopCount >= 1)
        #expect(fallback.startCount == 1)
    }

    @Test func failedFallbackStartReportsUnavailable() {
        let hid = FakeAngleSource(isAvailable: false)
        let fallback = FakeFallbackSource(startError: TestError.startFailed)
        let recorder = Recorder()
        let controller = makeController(
            hidSources: [hid],
            fallbackSources: [fallback],
            recorder: recorder
        )

        #expect(controller.start() == .unavailable)
        #expect(controller.mode == .unavailable)
        #expect(fallback.stopCount >= 1)
        #expect(recorder.modes.isEmpty)
    }

    @Test func runtimeHIDLossUsesEveryRetryBeforeSelectingFallback() async {
        let initial = FakeAngleSource()
        let retries = [
            FakeAngleSource(isAvailable: false),
            FakeAngleSource(startError: TestError.startFailed),
            FakeAngleSource(isAvailable: false),
        ]
        let fallback = FakeFallbackSource()
        let recorder = Recorder()
        let controller = makeController(
            hidSources: [initial] + retries,
            fallbackSources: [fallback],
            recovery: SensorRecovery(delays: [.zero, .zero, .zero]),
            recorder: recorder
        )

        controller.start()
        initial.reportUnavailable()
        await settle()
        await controller.waitForRecovery()

        #expect(controller.mode == .timedFallback)
        #expect(retries.map(\.startCount) == [0, 1, 0])
        #expect(fallback.startCount == 1)
        #expect(recorder.modes == [.sensor, .unavailable, .timedFallback])
    }

    @Test func runtimeRecoveryPromotesOnTheFirstSuccessfulRetry() async {
        let initial = FakeAngleSource()
        let unavailable = FakeAngleSource(isAvailable: false)
        let failed = FakeAngleSource(startError: TestError.startFailed)
        let recovered = FakeAngleSource()
        let unused = FakeAngleSource()
        let fallback = FakeFallbackSource()
        let controller = makeController(
            hidSources: [initial, unavailable, failed, recovered, unused],
            fallbackSources: [fallback],
            recovery: SensorRecovery(delays: [.zero, .zero, .zero, .zero])
        )

        controller.start()
        initial.reportUnavailable()
        await settle()
        await controller.waitForRecovery()

        #expect(controller.mode == .sensor)
        #expect(recovered.startCount == 1)
        #expect(unused.startCount == 0)
        #expect(fallback.startCount == 0)
    }

    @Test func wakeRetryPromotesFallbackToHIDAndRejectsLateFallbackSamples() async {
        let absent = FakeAngleSource(isAvailable: false)
        let promoted = FakeAngleSource()
        let fallback = FakeFallbackSource()
        let recorder = Recorder()
        let controller = makeController(
            hidSources: [absent, promoted],
            fallbackSources: [fallback],
            recovery: SensorRecovery(delays: [.zero]),
            recorder: recorder
        )

        controller.start()
        fallback.emit(.init(degrees: 80, timestamp: 1))
        await settle()
        controller.retryHID()
        await controller.waitForRecovery()
        fallback.emit(.init(degrees: 30, timestamp: 2))
        promoted.emit(.init(degrees: 70, timestamp: 3))
        await settle()

        #expect(controller.mode == .sensor)
        #expect(fallback.stopCount >= 1)
        #expect(recorder.samples.map(\.degrees) == [80, 70])
    }

    @Test func failedWakeRetryPreservesIdleFallbackThroughExhaustion() async {
        let fallbackAtLaunch = FakeFallbackSource()
        let fallbackAfterRecovery = FakeFallbackSource()
        let controller = makeController(
            hidSources: [
                FakeAngleSource(isAvailable: false),
                FakeAngleSource(isAvailable: false),
                FakeAngleSource(isAvailable: false),
            ],
            fallbackSources: [fallbackAtLaunch, fallbackAfterRecovery],
            recovery: SensorRecovery(delays: [.zero, .zero])
        )

        controller.start()
        controller.retryHID()
        #expect(controller.mode == .timedFallback)
        await controller.waitForRecovery()

        #expect(controller.mode == .timedFallback)
        #expect(fallbackAtLaunch.stopCount == 0)
        #expect(fallbackAfterRecovery.startCount == 0)
    }

    @Test func HIDStartFailureDuringWakeRetryKeepsOriginalFallbackUntilPromotion() async {
        let fallback = FakeFallbackSource()
        let failed = FakeAngleSource(startError: TestError.startFailed)
        let promoted = FakeAngleSource()
        let recorder = Recorder()
        let controller = makeController(
            hidSources: [FakeAngleSource(isAvailable: false), failed, promoted],
            fallbackSources: [fallback],
            recovery: SensorRecovery(delays: [.zero]),
            recorder: recorder
        )

        #expect(controller.start() == .timedFallback)
        controller.retryHID()
        await controller.waitForRecovery()
        #expect(controller.mode == .timedFallback)
        #expect(failed.startCount == 1)
        #expect(failed.stopCount >= 1)
        #expect(fallback.startCount == 1)
        #expect(fallback.stopCount == 0)
        fallback.emit(.init(degrees: 83, timestamp: 1))

        controller.retryHID()
        await controller.waitForRecovery()
        fallback.emit(.init(degrees: 20, timestamp: 2))
        failed.emit(.init(degrees: 10, timestamp: 2.5))
        failed.reportUnavailable()
        promoted.emit(.init(degrees: 70, timestamp: 3))
        await settle()

        #expect(controller.mode == .sensor)
        #expect(fallback.stopCount == 1)
        #expect(recorder.modes == [.timedFallback, .sensor])
        #expect(recorder.samples.map(\.degrees) == [83, 70])
    }

    @Test func backgroundSampleCannotBeOvertakenByLaterMainThreadSample() async {
        let hid = FakeAngleSource()
        let recorder = Recorder()
        let controller = makeController(hidSources: [hid], recorder: recorder)
        controller.start()

        emitOffMain(hid, .init(degrees: 101, timestamp: 1))
        hid.emit(.init(degrees: 100, timestamp: 2))
        await settle()

        #expect(recorder.samples.map(\.degrees) == [101, 100])
    }

    @Test func fallbackCloseRoutingIsModeRestrictedAndCancelsOnSessionRestriction() {
        let fallback = FakeFallbackSource()
        let controller = makeController(
            hidSources: [FakeAngleSource(isAvailable: false)],
            fallbackSources: [fallback]
        )

        #expect(!controller.beginFallbackClose())
        controller.start()
        #expect(controller.beginFallbackClose())
        #expect(fallback.beginCloseCount == 1)

        controller.setSessionRestricted(true)
        #expect(fallback.cancelCount == 1)
        #expect(!controller.beginFallbackClose())
        controller.setSessionRestricted(false)
        #expect(controller.beginFallbackClose())
        controller.cancelFallbackTransition()
        #expect(fallback.cancelCount == 2)
    }

    @Test func queuedFallbackTickIsDiscardedWhenTransitionIsCancelled() async {
        let fallback = FakeFallbackSource()
        let recorder = Recorder()
        let controller = makeController(
            hidSources: [FakeAngleSource(isAvailable: false)],
            fallbackSources: [fallback],
            recorder: recorder
        )
        controller.start()
        #expect(controller.beginFallbackClose())

        emitOffMain(fallback, .init(degrees: 44, timestamp: 1))
        controller.cancelFallbackTransition()
        await settle()
        #expect(recorder.samples.isEmpty)

        #expect(controller.beginFallbackClose())
        fallback.emit(.init(degrees: 103, timestamp: 2))
        #expect(recorder.samples.map(\.degrees) == [103])
    }

    @Test func fallbackFirstSampleIsDeliveredBeforeCloseRoutingReturns() {
        let first = AngleSample(degrees: 109, timestamp: 1)
        let fallback = FakeFallbackSource(sampleOnBegin: first)
        let recorder = Recorder()
        let controller = makeController(
            hidSources: [FakeAngleSource(isAvailable: false)],
            fallbackSources: [fallback],
            recorder: recorder
        )

        controller.start()
        #expect(controller.beginFallbackClose())
        #expect(recorder.samples == [first])
    }

    @Test func restrictedSessionSuppressesBothQueuedSourceKinds() async {
        let hid = FakeAngleSource()
        let recorder = Recorder()
        let controller = makeController(hidSources: [hid], recorder: recorder)

        controller.start()
        controller.setSessionRestricted(true)
        hid.emit(.init(degrees: 50, timestamp: 1))
        await settle()
        #expect(recorder.samples.isEmpty)

        controller.setSessionRestricted(false)
        hid.emit(.init(degrees: 49, timestamp: 2))
        await settle()
        #expect(recorder.samples.map(\.degrees) == [49])
    }

    @Test func queuedSampleFromBeforeLockDoesNotLeakAfterImmediateUnlock() async {
        let hid = FakeAngleSource()
        let recorder = Recorder()
        let controller = makeController(hidSources: [hid], recorder: recorder)
        controller.start()

        emitOffMain(hid, .init(degrees: 50, timestamp: 1))
        controller.setSessionRestricted(true)
        controller.setSessionRestricted(false)
        await settle()
        #expect(recorder.samples.isEmpty)

        hid.emit(.init(degrees: 49, timestamp: 2))
        #expect(recorder.samples.map(\.degrees) == [49])
    }

    @Test func disableEnableReprobesHIDAndRejectsOldCallbacks() async {
        let old = FakeAngleSource()
        let replacement = FakeAngleSource()
        let recorder = Recorder()
        let controller = makeController(
            hidSources: [old, replacement],
            recorder: recorder
        )

        controller.start()
        #expect(controller.setEnabled(false) == .unavailable)
        old.emit(.init(degrees: 20, timestamp: 1))
        old.reportUnavailable()
        await settle()
        #expect(recorder.samples.isEmpty)
        #expect(controller.mode == .unavailable)

        #expect(controller.setEnabled(true) == .sensor)
        replacement.emit(.init(degrees: 65, timestamp: 2))
        await settle()
        #expect(recorder.samples.map(\.degrees) == [65])
        #expect(old.stopCount >= 1)
        #expect(replacement.startCount == 1)
    }

    @Test func repeatedRetryCancelsPriorRecoveryAndTerminationLeavesNoSource() async {
        let initial = FakeAngleSource(isAvailable: false)
        let secondRetry = FakeAngleSource()
        let fallback = FakeFallbackSource()
        let sleeper = ControlledSleeper()
        let controller = makeController(
            hidSources: [initial, secondRetry],
            fallbackSources: [fallback],
            recovery: SensorRecovery(delays: [.seconds(1)]),
            recoverySleep: sleeper.sleep
        )

        controller.start()
        controller.retryHID()
        await sleeper.waitForCalls(1)
        controller.retryHID()
        await sleeper.waitForCalls(2)
        await sleeper.resumeAll()
        await controller.waitForRecovery()
        #expect(controller.mode == .sensor)

        controller.stop()
        secondRetry.emit(.init(degrees: 40, timestamp: 4))
        await settle()
        #expect(controller.mode == .unavailable)
        #expect(!controller.isEnabled)
        #expect(secondRetry.stopCount >= 1)
    }
}

@MainActor
private func makeController(
    hidSources: [FakeAngleSource],
    fallbackSources: [FakeFallbackSource] = [],
    fallbackFactory: InputSourceController.FallbackFactory? = nil,
    recovery: SensorRecovery = SensorRecovery(delays: [.zero]),
    recoverySleep: @escaping SensorRecovery.Sleeper = { _ in },
    recorder: Recorder = Recorder()
) -> InputSourceController {
    var hidIndex = 0
    var fallbackIndex = 0
    return InputSourceController(
        hidFactory: { unavailable in
            let index = min(hidIndex, hidSources.count - 1)
            hidIndex += 1
            let source = hidSources[index]
            source.unavailable = unavailable
            return source
        },
        fallbackFactory: fallbackFactory ?? {
            guard fallbackIndex < fallbackSources.count else { return nil }
            defer { fallbackIndex += 1 }
            return fallbackSources[fallbackIndex]
        },
        recovery: recovery,
        recoverySleep: recoverySleep,
        onSample: { recorder.samples.append($0) },
        onModeChanged: { recorder.modes.append($0) }
    )
}

private enum TestError: Error {
    case startFailed
}

private final class Recorder: @unchecked Sendable {
    var samples: [AngleSample] = []
    var modes: [InputSourceMode] = []
}

private final class FakeAngleSource: LidAngleSource, @unchecked Sendable {
    let isAvailable: Bool
    var unavailable: (@Sendable () -> Void)?

    private let lock = NSLock()
    private let startError: Error?
    private var handler: (@Sendable (AngleSample) -> Void)?
    private var _startCount = 0
    private var _stopCount = 0

    init(isAvailable: Bool = true, startError: Error? = nil) {
        self.isAvailable = isAvailable
        self.startError = startError
    }

    var startCount: Int { locked { _startCount } }
    var stopCount: Int { locked { _stopCount } }

    func start(_ handler: @escaping @Sendable (AngleSample) -> Void) throws {
        lock.lock()
        _startCount += 1
        self.handler = handler
        let error = startError
        lock.unlock()
        if let error { throw error }
    }

    func stop() {
        lock.lock()
        _stopCount += 1
        lock.unlock()
    }

    func emit(_ sample: AngleSample) {
        let callback = locked { handler }
        callback?(sample)
    }

    func reportUnavailable() {
        unavailable?()
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class FakeFallbackSource: FallbackAngleSource, @unchecked Sendable {
    let isAvailable: Bool

    private let lock = NSLock()
    private let startError: Error?
    private let sampleOnBegin: AngleSample?
    private var handler: (@Sendable (AngleSample) -> Void)?
    private var _startCount = 0
    private var _stopCount = 0
    private var _beginCloseCount = 0
    private var _cancelCount = 0

    init(
        isAvailable: Bool = true,
        startError: Error? = nil,
        sampleOnBegin: AngleSample? = nil
    ) {
        self.isAvailable = isAvailable
        self.startError = startError
        self.sampleOnBegin = sampleOnBegin
    }

    var startCount: Int { locked { _startCount } }
    var stopCount: Int { locked { _stopCount } }
    var beginCloseCount: Int { locked { _beginCloseCount } }
    var cancelCount: Int { locked { _cancelCount } }

    func start(_ handler: @escaping @Sendable (AngleSample) -> Void) throws {
        lock.lock()
        _startCount += 1
        self.handler = handler
        let error = startError
        lock.unlock()
        if let error { throw error }
    }

    func stop() {
        lock.lock()
        _stopCount += 1
        lock.unlock()
    }

    func beginClose() {
        lock.lock()
        _beginCloseCount += 1
        let handler = self.handler
        let sample = sampleOnBegin
        lock.unlock()
        if let sample { handler?(sample) }
    }

    func cancelTransition() {
        lock.lock()
        _cancelCount += 1
        lock.unlock()
    }

    func emit(_ sample: AngleSample) {
        let callback = locked { handler }
        callback?(sample)
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class ControlledSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func sleep(_ duration: Duration) async throws {
        try Task.checkCancellation()
        await withCheckedContinuation { continuation in
            lock.withLock { continuations.append(continuation) }
        }
        try Task.checkCancellation()
    }

    func waitForCalls(_ count: Int) async {
        while callCount < count { await Task.yield() }
    }

    func resumeAll() async {
        let pending = lock.withLock {
            let pending = continuations
            continuations.removeAll()
            return pending
        }
        pending.forEach { $0.resume() }
        await Task.yield()
    }

    private var callCount: Int {
        lock.withLock { continuations.count }
    }
}

private func settle() async {
    for _ in 0..<10 { await Task.yield() }
}

private func emitOffMain(_ source: FakeAngleSource, _ sample: AngleSample) {
    let emitted = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        source.emit(sample)
        emitted.signal()
    }
    emitted.wait()
}

private func emitOffMain(_ source: FakeFallbackSource, _ sample: AngleSample) {
    let emitted = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        source.emit(sample)
        emitted.signal()
    }
    emitted.wait()
}
