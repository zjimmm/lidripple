import Foundation

/// Conditions a raw sensor stream into something a state machine can trust.
///
/// Three jobs, per spec section 9.2 and plan deviation 1:
///  - one-pole low-pass on angle, removing sensor noise
///  - a deadband on the output, so micro-movement does not move the committed
///    angle at all
///  - a separately smoothed velocity estimate, because the raw derivative of a
///    15 Hz-filtered signal at 60 Hz still crosses the 5 deg/s direction gate
///    on noise alone
public struct AngleFilter {
    private let cutoffHz: Double
    private let velocitySmoothingHz: Double
    private let deadband: Double

    private var filtered: Double?
    private var committed: Double = 0
    private var lastTimestamp: TimeInterval?

    /// Degrees per second. Negative means closing.
    public private(set) var velocity: Double = 0

    public init(tuning: FoldTuning) {
        self.cutoffHz = tuning.filterCutoffHz
        self.velocitySmoothingHz = tuning.velocitySmoothingHz
        self.deadband = tuning.deadbandDegrees
    }

    /// Returns the committed (deadbanded) angle for this sample.
    public mutating func process(_ sample: AngleSample) -> Double {
        guard let previous = filtered, let previousTime = lastTimestamp else {
            filtered = sample.degrees
            committed = sample.degrees
            lastTimestamp = sample.timestamp
            velocity = 0
            return committed
        }

        let dt = max(sample.timestamp - previousTime, 1e-6)
        let angleAlpha = 1 - exp(-2 * .pi * cutoffHz * dt)
        let next = previous + angleAlpha * (sample.degrees - previous)

        let instantaneous = (next - previous) / dt
        let velocityAlpha = 1 - exp(-2 * .pi * velocitySmoothingHz * dt)
        velocity += velocityAlpha * (instantaneous - velocity)

        filtered = next
        lastTimestamp = sample.timestamp

        if abs(next - committed) > deadband {
            committed = next
        }
        return committed
    }
}
