import Foundation

/// Converts lid angle samples into fold state.
///
/// This type is the product's feel, and per spec section 8.1 it imports only
/// Foundation: no IOKit, no Metal, no AppKit. That is what makes the animation
/// testable from recorded traces instead of by closing a laptop repeatedly.
public final class FoldDriver {
    private let tuning: FoldTuning
    private var filter: AngleFilter
    private var spring: Spring

    private var phase: FoldPhase = .idle
    private var lastTimestamp: TimeInterval?

    /// Direction gate: tracks how long motion has been consistently one way
    /// and how far it has travelled. Both must clear before a direction
    /// commits (spec section 9.2 plus plan deviation 2).
    private var gateIsClosing = false
    private var gateSince: TimeInterval?
    private var gateStartAngle: Double?

    public private(set) var state: FoldState = .idle

    public init(tuning: FoldTuning = .default) {
        self.tuning = tuning
        self.filter = AngleFilter(tuning: tuning)
        self.spring = Spring(tuning: tuning)
    }

    @discardableResult
    public func ingest(_ sample: AngleSample) -> FoldState {
        let angle = filter.process(sample)
        let velocity = filter.velocity
        let dt = lastTimestamp.map { max(sample.timestamp - $0, 0) } ?? 0
        lastTimestamp = sample.timestamp

        updateDirectionGate(angle: angle, velocity: velocity, now: sample.timestamp)
        advancePhase(angle: angle)
        return publish(angle: angle, velocity: velocity, dt: dt)
    }

    @discardableResult
    public func signalSleep() -> FoldState {
        phase = .sealed
        spring.reset(to: 1.0)
        state = FoldState(phase: .sealed, progress: 1.0, velocity: 0)
        return state
    }

    @discardableResult
    public func reset() -> FoldState {
        phase = .idle
        spring.reset(to: 0)
        filter = AngleFilter(tuning: tuning)
        lastTimestamp = nil
        clearGate()
        state = .idle
        return state
    }

    // MARK: - Direction gate

    private func updateDirectionGate(angle: Double, velocity: Double, now: TimeInterval) {
        let closing = velocity < -tuning.directionVelocityThreshold
        let opening = velocity > tuning.directionVelocityThreshold

        guard closing || opening else { clearGate(); return }

        if gateSince == nil || gateIsClosing != closing {
            gateIsClosing = closing
            gateSince = now
            gateStartAngle = angle
        }
    }

    private func clearGate() {
        gateSince = nil
        gateStartAngle = nil
    }

    /// True when motion has been consistently in `closing` direction for long
    /// enough *and* travelled far enough to be real rather than noise.
    private func directionCommitted(closing: Bool, angle: Double, now: TimeInterval) -> Bool {
        guard gateIsClosing == closing,
              let since = gateSince,
              let start = gateStartAngle,
              now - since >= tuning.directionHoldSeconds,
              abs(angle - start) >= tuning.directionMinTravelDegrees
        else { return false }
        return true
    }

    // MARK: - Phase machine

    private func advancePhase(angle: Double) {
        let now = lastTimestamp ?? 0
        switch phase {
        case .idle:
            if angle < tuning.armAngle, directionCommitted(closing: true, angle: angle, now: now) {
                phase = .armed
            }
        case .armed:
            if angle < tuning.foldStartAngle {
                phase = .folding
            } else if angle > tuning.armAngle + tuning.phaseHysteresisDegrees,
                      directionCommitted(closing: false, angle: angle, now: now) {
                phase = .idle
            }
        case .folding:
            if angle < tuning.sealAngle {
                phase = .sealed
                spring.reset(to: 1.0)
            } else if directionCommitted(closing: false, angle: angle, now: now) {
                phase = .unfolding
            }
        case .unfolding:
            if directionCommitted(closing: true, angle: angle, now: now) {
                phase = .folding
            } else if spring.value <= 0.001, angle > tuning.idleReturnAngle {
                phase = .idle
                spring.reset(to: 0)
            }
        case .sealed:
            break  // only signalSleep, reset, or the unlock path leave sealed
        }
    }

    // MARK: - Output

    /// Task 6 keeps progress pinned to the phase so transitions can be tested
    /// in isolation. Task 7 replaces this with the spring-driven version.
    private func publish(angle: Double, velocity: Double, dt: TimeInterval) -> FoldState {
        let progress: Double
        switch phase {
        case .idle, .armed: progress = 0
        case .sealed: progress = 1.0
        case .folding, .unfolding: progress = spring.value
        }
        state = FoldState(phase: phase, progress: progress, velocity: 0)
        return state
    }
}
