import Foundation
import Testing
@testable import LidRippleCore
@testable import LidRippleSensor

@Test func fallbackCloseIsIdleUntilTriggeredAndTraversesTheRealDriver() throws {
    let scheduler = ManualEventAngleScheduler()
    let sink = EventSampleSink()
    let source = try EventAngleSource(
        foldTuning: .default,
        eventTuning: .default,
        clock: { 100 },
        scheduler: scheduler
    )
    try source.start { sink.append($0) }

    #expect(scheduler.taskCount == 0)
    #expect(!source.hasScheduledTransition)

    source.beginClose()
    #expect(sink.samples.count == 1)
    #expect(source.hasScheduledTransition)
    scheduler.runActiveTasks(untilIdle: true)

    let samples = sink.samples
    #expect(samples.count == 51)
    #expect(!source.hasScheduledTransition)
    #expect(scheduler.activeTaskCount == 0)
    #expect(zip(samples, samples.dropFirst()).allSatisfy { first, second in
        second.timestamp > first.timestamp && second.degrees < first.degrees
    })
    #expect(samples.last?.degrees == FoldTuning.default.sealAngle - 1)
    #expect(abs((samples.last?.timestamp ?? 0) - (samples.first?.timestamp ?? 0)
                - EventAngleTuning.default.programDuration) < 1e-9)

    let driver = FoldDriver()
    let phaseHistory = samples.map { (sample: $0, phase: driver.ingest($0).phase) }
    let phases = phaseHistory.map(\.phase)
    #expect(phases.contains(.armed))
    #expect(phases.contains(.folding))
    #expect(phases.last == .sealed)
    let foldStart = try #require(phaseHistory.first { $0.phase == .folding }?.sample.timestamp)
    let sealed = try #require(phaseHistory.first { $0.phase == .sealed }?.sample.timestamp)
    #expect(abs((sealed - foldStart) - EventAngleTuning.default.duration) <= 2.0 / 60.0)
}

@Test func duplicateCloseDoesNotRestartRunningOrCompletedProgram() throws {
    let scheduler = ManualEventAngleScheduler()
    let sink = EventSampleSink()
    let source = try EventAngleSource(
        foldTuning: .default,
        eventTuning: .default,
        clock: { 10 },
        scheduler: scheduler
    )
    try source.start { sink.append($0) }

    source.beginClose()
    let firstTask = try #require(scheduler.tasks.first)
    firstTask.fire()
    let countBeforeDuplicate = sink.samples.count
    source.beginClose()

    #expect(!firstTask.isCancelled)
    #expect(scheduler.taskCount == 1)
    #expect(sink.samples.count == countBeforeDuplicate)
    scheduler.runActiveTasks(untilIdle: true)
    let countAfterSeal = sink.samples.count
    source.beginClose()
    #expect(scheduler.taskCount == 1)
    #expect(sink.samples.count == countAfterSeal)

    source.cancelTransition()
    source.beginClose()
    #expect(scheduler.taskCount == 2)
    scheduler.runActiveTasks(untilIdle: true)
    let timestamps = sink.samples.map(\.timestamp)
    #expect(zip(timestamps, timestamps.dropFirst()).allSatisfy(<))
    #expect(sink.samples.last?.degrees == FoldTuning.default.sealAngle - 1)
}

@Test func cancelWaitsForInFlightDeliveryAndRejectsStaleTick() throws {
    let scheduler = ManualEventAngleScheduler()
    let source = try EventAngleSource(
        foldTuning: .default,
        eventTuning: .default,
        clock: { 0 },
        scheduler: scheduler
    )
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let beginReturned = DispatchSemaphore(value: 0)
    let cancelStarted = DispatchSemaphore(value: 0)
    let cancelReturned = DispatchSemaphore(value: 0)
    let sink = EventSampleSink()
    try source.start { sample in
        entered.signal()
        _ = release.wait(timeout: .now() + 2)
        sink.append(sample)
    }

    DispatchQueue.global().async {
        source.beginClose()
        beginReturned.signal()
    }
    #expect(entered.wait(timeout: .now() + 2) == .success)
    DispatchQueue.global().async {
        cancelStarted.signal()
        source.cancelTransition()
        cancelReturned.signal()
    }
    #expect(cancelStarted.wait(timeout: .now() + 2) == .success)
    #expect(cancelReturned.wait(timeout: .now() + 0.05) == .timedOut)
    release.signal()
    #expect(cancelReturned.wait(timeout: .now() + 2) == .success)
    #expect(beginReturned.wait(timeout: .now() + 2) == .success)
    #expect(sink.samples.count == 1)
    #expect(scheduler.activeTaskCount == 0)
    scheduler.tasks.forEach { $0.fireEvenIfCancelled() }
    #expect(sink.samples.count == 1)
}

@Test func cancelAndStopReleaseScheduledWorkAndRejectStaleTicks() throws {
    let scheduler = ManualEventAngleScheduler()
    let sink = EventSampleSink()
    let source = try EventAngleSource(
        foldTuning: .default,
        eventTuning: .default,
        clock: { 0 },
        scheduler: scheduler
    )
    try source.start { sink.append($0) }

    source.beginClose()
    let stale = try #require(scheduler.tasks.first)
    let countBeforeCancel = sink.samples.count
    source.cancelTransition()
    stale.fireEvenIfCancelled()
    #expect(sink.samples.count == countBeforeCancel)
    #expect(!source.hasScheduledTransition)

    source.beginClose()
    let latest = try #require(scheduler.tasks.last)
    source.stop()
    latest.fireEvenIfCancelled()
    #expect(scheduler.activeTaskCount == 0)
    #expect(!source.hasScheduledTransition)
}

@Test func stopFromFirstSampleHandlerDoesNotDeadlockOrCreateATimer() throws {
    let scheduler = ManualEventAngleScheduler()
    let holder = EventSourceHolder()
    let source = try EventAngleSource(
        foldTuning: .default,
        eventTuning: .default,
        clock: { 0 },
        scheduler: scheduler
    )
    holder.source = source
    try source.start { _ in holder.source?.stop() }

    source.beginClose()

    #expect(scheduler.taskCount == 0)
    #expect(!source.hasScheduledTransition)
}

@Test func invalidFallbackTuningFailsBeforeScheduling() {
    #expect(throws: EventAngleSourceError.invalidTuning) {
        try EventAngleSource(eventTuning: .init(duration: 0))
    }
    #expect(throws: EventAngleSourceError.invalidTuning) {
        try EventAngleSource(eventTuning: .init(
            armFraction: 0.5,
            foldStartFraction: 0.4
        ))
    }
}

private final class EventSampleSink: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [AngleSample] = []

    var samples: [AngleSample] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ sample: AngleSample) {
        lock.lock()
        storage.append(sample)
        lock.unlock()
    }
}

private final class EventSourceHolder: @unchecked Sendable {
    var source: EventAngleSource?
}

private final class ManualEventAngleScheduler: EventAngleScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ManualEventAngleTask] = []

    var tasks: [ManualEventAngleTask] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
    var taskCount: Int { tasks.count }
    var activeTaskCount: Int { tasks.filter { !$0.isCancelled }.count }

    func schedule(
        every interval: TimeInterval,
        _ action: @escaping @Sendable () -> Void
    ) -> any EventAngleScheduledTask {
        let task = ManualEventAngleTask(interval: interval, action: action)
        lock.lock()
        storage.append(task)
        lock.unlock()
        return task
    }

    func runActiveTasks(untilIdle: Bool) {
        repeat {
            let active = tasks.filter { !$0.isCancelled }
            active.forEach { $0.fire() }
            if !untilIdle || active.isEmpty { return }
        } while activeTaskCount > 0
    }
}

private final class ManualEventAngleTask: EventAngleScheduledTask, @unchecked Sendable {
    let interval: TimeInterval
    private let action: @Sendable () -> Void
    private let lock = NSLock()
    private var cancelled = false

    init(interval: TimeInterval, action: @escaping @Sendable () -> Void) {
        self.interval = interval
        self.action = action
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func fire() {
        guard !isCancelled else { return }
        action()
    }

    func fireEvenIfCancelled() { action() }
}
