import Foundation

/// A damped second-order system integrated at a fixed substep.
///
/// Spec section 9.1: the lid angle supplies the *target*, and this chases it.
/// That indirection is what produces viscous slow closes, continuous
/// reversal, and jitter absorption from one mechanism.
///
/// Substepping at a fixed interval rather than the incoming `dt` matters: the
/// sensor cadence is not guaranteed, and semi-implicit Euler at 220 stiffness
/// diverges on a long frame.
public struct Spring {
    private let stiffness: Double
    private let damping: Double
    private let substep: Double

    public private(set) var value: Double
    public private(set) var velocity: Double = 0

    public init(tuning: FoldTuning, value: Double = 0) {
        self.stiffness = tuning.stiffness
        self.damping = tuning.damping
        self.substep = tuning.substepSeconds
        self.value = value
    }

    public mutating func step(target: Double, dt: TimeInterval) {
        guard dt > 0 else { return }
        var remaining = dt
        while remaining > 0 {
            let h = min(substep, remaining)
            let acceleration = stiffness * (target - value) - damping * velocity
            velocity += acceleration * h
            value += velocity * h
            remaining -= h
        }
    }

    public mutating func reset(to value: Double) {
        self.value = value
        self.velocity = 0
    }
}
