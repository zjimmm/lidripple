import Foundation
import LidRippleCore

/// A recorded sequence of real lid angles.
///
/// Spec section 12 makes this the project's highest-value test
/// infrastructure: it is the only way to exercise the driver against genuine
/// hand motion deterministically and repeatedly.
public struct Trace: Codable, Equatable, Sendable {
    public struct Sample: Codable, Equatable, Sendable {
        public let t: Double
        public let deg: Double

        public init(t: Double, deg: Double) {
            self.t = t
            self.deg = deg
        }
    }

    public let name: String
    public let recordedAt: Date
    public let deviceModel: String
    public let samples: [Sample]

    public init(name: String, recordedAt: Date, deviceModel: String, samples: [Sample]) {
        self.name = name
        self.recordedAt = recordedAt
        self.deviceModel = deviceModel
        self.samples = samples
    }

    /// Samples as driver input, rebased so the first timestamp is 0. Recorded
    /// timestamps come from `systemUptime` and are large and machine-specific;
    /// rebasing makes fixtures comparable across machines.
    public var angleSamples: [AngleSample] {
        guard let first = samples.first else { return [] }
        return samples.map { AngleSample(degrees: $0.deg, timestamp: $0.t - first.t) }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> Trace {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Trace.self, from: data)
    }
}
