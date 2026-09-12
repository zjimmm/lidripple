import Foundation
import LidRippleCore

/// Accumulates live samples into a `Trace`.
public final class TraceRecorder {
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
