import Foundation
import LidRippleCore

/// Replays a trace in real time, honoring the gaps between samples.
///
/// Tests that only need determinism should iterate `trace.angleSamples`
/// directly and skip this entirely; this exists for `lidripple-trace replay`
/// and for driving the app without touching the lid.
public final class TraceReplaySource: LidAngleSource, @unchecked Sendable {
    private let samples: [AngleSample]
    private let speed: Double
    private let queue = DispatchQueue(label: "com.lidripple.replay", qos: .userInteractive)
    private var cancelled = false

    /// - Parameter speed: playback multiplier. 1.0 is real time.
    public init(trace: Trace, speed: Double = 1.0) {
        self.samples = trace.angleSamples
        self.speed = max(speed, 0.01)
    }

    public var isAvailable: Bool { true }

    public func start(_ handler: @escaping @Sendable (AngleSample) -> Void) throws {
        queue.async { [samples, speed, self] in
            let start = DispatchTime.now()
            for sample in samples {
                if lockedIsCancelled() { return }
                let offset = sample.timestamp / speed
                let due = start + .nanoseconds(Int(offset * 1_000_000_000))
                let now = DispatchTime.now()
                if due > now {
                    let waitNanos = due.uptimeNanoseconds - now.uptimeNanoseconds
                    Thread.sleep(forTimeInterval: Double(waitNanos) / 1_000_000_000)
                }
                if lockedIsCancelled() { return }
                handler(sample)
            }
        }
    }

    public func stop() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    private let lock = NSLock()
    private func lockedIsCancelled() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
}
