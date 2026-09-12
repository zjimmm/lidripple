import Foundation
import LidRippleCore

/// Accumulates live samples into a `Trace`.
///
/// `@unchecked Sendable`: all mutable state (`samples`) is guarded by `lock`,
/// the same pattern `HIDAngleSource` uses for the same reason — the CLI's
/// `record` command captures this recorder in the `@Sendable` handler closure
/// passed to `LidAngleSource.start(_:)`, which runs on the sensor's polling
/// queue rather than the caller's thread.
public final class TraceRecorder: @unchecked Sendable {
    private let name: String
    private let deviceModel: String
    private let lock = NSLock()
    private var samples: [Trace.Sample] = []

    public init(name: String, deviceModel: String) {
        self.name = name
        self.deviceModel = deviceModel
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return samples.count
    }

    /// Safe to call from the sensor's polling queue.
    public func record(_ sample: AngleSample) {
        lock.lock(); defer { lock.unlock() }
        samples.append(Trace.Sample(t: sample.timestamp, deg: sample.degrees))
    }

    public func finish(at date: Date = Date()) -> Trace {
        lock.lock(); defer { lock.unlock() }
        return Trace(name: name, recordedAt: date, deviceModel: deviceModel, samples: samples)
    }
}
