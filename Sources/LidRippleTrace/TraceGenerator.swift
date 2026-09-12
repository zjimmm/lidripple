import Foundation
import LidRippleCore

/// Deterministic synthetic lid traces.
///
/// These cover the six motions named in spec section 12 and are generated
/// rather than recorded so the suite runs identically on any machine,
/// including one with no lid sensor.
public enum TraceGenerator {
    private static let hz = 60.0
    private static let epoch = Date(timeIntervalSince1970: 1_789_000_000)

    public static var all: [Trace] {
        [slowClose(), slam(), hesitantClose(), stopAndReopen(), wiggleAtRest(), closeReopenClose()]
    }

    /// 120 degrees to 5 at 40 deg/s: the viscous case.
    public static func slowClose() -> Trace {
        build("slow-close", segments: [.ramp(from: 120, to: 5, degreesPerSecond: 40)])
    }

    /// 120 degrees to 5 at 600 deg/s: faster than the eye, tests the clamp.
    public static func slam() -> Trace {
        build("slam", segments: [.ramp(from: 120, to: 5, degreesPerSecond: 600)])
    }

    /// Closing in three bursts with pauses, the way someone half-distracted does it.
    public static func hesitantClose() -> Trace {
        build("hesitant-close", segments: [
            .ramp(from: 115, to: 80, degreesPerSecond: 150),
            .hold(at: 80, seconds: 0.30),
            .ramp(from: 80, to: 45, degreesPerSecond: 90),
            .hold(at: 45, seconds: 0.40),
            .ramp(from: 45, to: 6, degreesPerSecond: 200),
        ])
    }

    /// Closes to 45, changes mind, opens back up. The reversal case.
    public static func stopAndReopen() -> Trace {
        build("stop-and-reopen", segments: [
            .ramp(from: 110, to: 45, degreesPerSecond: 160),
            .hold(at: 45, seconds: 0.15),
            .ramp(from: 45, to: 100, degreesPerSecond: 160),
            .hold(at: 100, seconds: 0.50),
        ])
    }

    /// A hand resting on an open lid: two seconds of sub-degree noise.
    /// Deterministic by construction, no RNG.
    public static func wiggleAtRest() -> Trace {
        var samples: [Trace.Sample] = []
        let count = Int(2.0 * hz)
        for i in 0..<count {
            let wobble = 0.22 * sin(Double(i) * 0.9) + 0.10 * sin(Double(i) * 2.7)
            samples.append(Trace.Sample(t: Double(i) / hz, deg: 90 + wobble))
        }
        return Trace(name: "wiggle-at-rest", recordedAt: epoch, deviceModel: "synthetic", samples: samples)
    }

    /// Close, reopen partway, close again. Exercises re-entrancy.
    public static func closeReopenClose() -> Trace {
        build("close-reopen-close", segments: [
            .ramp(from: 110, to: 40, degreesPerSecond: 180),
            .ramp(from: 40, to: 95, degreesPerSecond: 180),
            // 0.45 s, not 0.20: the spring needs ~0.3 s to settle to zero, and
            // Task 10 asserts this trace genuinely passes through idle.
            .hold(at: 95, seconds: 0.45),
            .ramp(from: 95, to: 5, degreesPerSecond: 180),
        ])
    }

    // MARK: - Building blocks

    private enum Segment {
        case ramp(from: Double, to: Double, degreesPerSecond: Double)
        case hold(at: Double, seconds: Double)
    }

    private static func build(_ name: String, segments: [Segment]) -> Trace {
        var samples: [Trace.Sample] = []
        var t = 0.0
        for segment in segments {
            switch segment {
            case let .ramp(from, to, rate):
                let steps = max(Int((abs(to - from) / rate) * hz), 1)
                for i in 1...steps {
                    let fraction = Double(i) / Double(steps)
                    t += 1 / hz
                    samples.append(Trace.Sample(t: t, deg: from + (to - from) * fraction))
                }
            case let .hold(angle, seconds):
                for _ in 0..<max(Int(seconds * hz), 1) {
                    t += 1 / hz
                    samples.append(Trace.Sample(t: t, deg: angle))
                }
            }
        }
        return Trace(name: name, recordedAt: epoch, deviceModel: "synthetic", samples: samples)
    }
}
