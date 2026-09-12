import Foundation
import LidRippleCore

public enum EventAngleSourceError: Error, Equatable {
    case alreadyStarted
    case invalidTuning
}

protocol EventAngleScheduledTask: Sendable {
    func cancel()
}

protocol EventAngleScheduling: Sendable {
    func schedule(
        every interval: TimeInterval,
        _ action: @escaping @Sendable () -> Void
    ) -> any EventAngleScheduledTask
}

struct DispatchEventAngleScheduler: EventAngleScheduling {
    func schedule(
        every interval: TimeInterval,
        _ action: @escaping @Sendable () -> Void
    ) -> any EventAngleScheduledTask {
        DispatchEventAngleTask(interval: interval, action: action)
    }
}

private final class DispatchEventAngleTask: EventAngleScheduledTask, @unchecked Sendable {
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?

    init(interval: TimeInterval, action: @escaping @Sendable () -> Void) {
        let timer = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "com.lidripple.event-angle", qos: .userInteractive)
        )
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(1))
        timer.setEventHandler(handler: action)
        self.timer = timer
        timer.resume()
    }

    func cancel() {
        lock.lock()
        let timer = self.timer
        self.timer = nil
        lock.unlock()
        timer?.cancel()
    }

    deinit { cancel() }
}

/// Sensor-less input that turns a public system close event into the same
/// angle samples consumed by `FoldDriver`.
///
/// The source owns no timer while merely started. `beginClose()` creates one
/// bounded program, and the timer is released at its terminal sample. Wake and
/// unlock remain the lifecycle coordinator's fresh scripted-unfold path.
public final class EventAngleSource: LidAngleSource, @unchecked Sendable {
    public typealias Clock = @Sendable () -> TimeInterval

    public let isAvailable = true

    private let foldTuning: FoldTuning
    private let eventTuning: EventAngleTuning
    private let clock: Clock
    private let scheduler: any EventAngleScheduling
    // Delivery happens while this lock is held so cancellation cannot return
    // between selecting a sample and calling its handler. Handlers may stop or
    // cancel their own source, hence the recursive lock.
    private let lock = NSRecursiveLock()

    private var handler: (@Sendable (AngleSample) -> Void)?
    private var scheduledTask: (any EventAngleScheduledTask)?
    private var generation: UInt64 = 0
    private var sampleIndex = 0
    private var sampleCount = 0
    private var closeRequested = false
    private var programStart: TimeInterval = 0
    private var lastTimestamp: TimeInterval?

    public convenience init(
        foldTuning: FoldTuning = .default,
        eventTuning: EventAngleTuning = .default
    ) throws {
        try self.init(
            foldTuning: foldTuning,
            eventTuning: eventTuning,
            clock: { ProcessInfo.processInfo.systemUptime },
            scheduler: DispatchEventAngleScheduler()
        )
    }

    init(
        foldTuning: FoldTuning,
        eventTuning: EventAngleTuning,
        clock: @escaping Clock,
        scheduler: any EventAngleScheduling
    ) throws {
        self.foldTuning = foldTuning
        self.eventTuning = try eventTuning.validated()
        self.clock = clock
        self.scheduler = scheduler
    }

    public func start(_ handler: @escaping @Sendable (AngleSample) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        guard self.handler == nil else { throw EventAngleSourceError.alreadyStarted }
        generation &+= 1
        self.handler = handler
    }

    public func stop() {
        lock.lock()
        generation &+= 1
        handler = nil
        let task = scheduledTask
        scheduledTask = nil
        sampleIndex = 0
        sampleCount = 0
        closeRequested = false
        lock.unlock()
        task?.cancel()
    }

    /// Starts the deterministic close program once per wake/unlock cycle.
    /// Duplicate system notifications cannot rewind a running or sealed fold.
    public func beginClose() {
        lock.lock()
        guard handler != nil, !closeRequested else {
            lock.unlock()
            return
        }
        closeRequested = true
        generation &+= 1
        let cycle = generation
        sampleIndex = 0
        sampleCount = max(Int((eventTuning.programDuration * eventTuning.framesPerSecond).rounded()) + 1, 2)
        let interval = 1 / eventTuning.framesPerSecond
        let now = clock()
        programStart = max(now, (lastTimestamp ?? (now - interval)) + interval)
        lock.unlock()

        emit(cycle: cycle)

        lock.lock()
        let shouldSchedule = generation == cycle && handler != nil && sampleIndex < sampleCount
        lock.unlock()
        guard shouldSchedule else { return }

        let task = scheduler.schedule(every: interval) { [weak self] in
            self?.emit(cycle: cycle)
        }
        lock.lock()
        if generation == cycle, handler != nil, sampleIndex < sampleCount {
            scheduledTask = task
            lock.unlock()
        } else {
            lock.unlock()
            task.cancel()
        }
    }

    public func cancelTransition() {
        lock.lock()
        generation &+= 1
        let task = scheduledTask
        scheduledTask = nil
        sampleIndex = 0
        sampleCount = 0
        closeRequested = false
        lock.unlock()
        task?.cancel()
    }

    var hasScheduledTransition: Bool {
        lock.lock()
        defer { lock.unlock() }
        return scheduledTask != nil
    }

    private func emit(cycle: UInt64) {
        lock.lock()
        guard generation == cycle,
              let handler,
              sampleIndex < sampleCount
        else {
            lock.unlock()
            return
        }
        let index = sampleIndex
        sampleIndex += 1
        let isTerminal = sampleIndex == sampleCount
        let fraction = Double(index) / Double(sampleCount - 1)
        let timestamp = programStart + Double(index) / eventTuning.framesPerSecond
        lastTimestamp = timestamp
        let sample = AngleSample(
            degrees: eventTuning.angle(at: fraction, fold: foldTuning),
            timestamp: timestamp
        )
        let task: (any EventAngleScheduledTask)?
        if isTerminal {
            task = scheduledTask
            scheduledTask = nil
        } else {
            task = nil
        }
        handler(sample)
        lock.unlock()
        task?.cancel()
    }

    deinit { stop() }
}
