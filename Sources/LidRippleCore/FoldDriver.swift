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

    /// Set while a scripted (angle-free) unfold is running. Spec FR-10.
    private var scriptedUnfoldStart: TimeInterval?
    private var lastTarget: Double = 0

    public private(set) var state: FoldState = .idle

    public init(tuning: FoldTuning = .default) {
        self.tuning = tuning
        self.filter = AngleFilter(tuning: tuning)
        self.spring = Spring(tuning: tuning)
    }

    @discardableResult
    public func ingest(_ sample: AngleSample) -> FoldState {
        if scriptedUnfoldStart != nil {
            // A real angle sample arrived while a scripted (angle-free) unfold
            // was in progress. `publish()` has no awareness of the scripted
            // curve, so letting both drive the spring/progress at once
            // corrupts it (see the final-review fix wave notes). The safest
            // behavior is to let the real angle take over: drop the scripted
            // unfold and fall through to the normal phase-machine path, which
            // continues from `.unfolding` (set by `beginScriptedUnfold`)
            // tracking the genuine angle from here on.
            scriptedUnfoldStart = nil
        }
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
        // Clear any in-flight scripted unfold: otherwise the next `tick(now:)`
        // would still take the `scriptedUnfoldStart` branch and drive `phase`
        // back out of `.sealed`, undoing the seal.
        scriptedUnfoldStart = nil
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
        scriptedUnfoldStart = nil
        lastTarget = 0
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
            } else if spring.value <= tuning.springSettleEpsilon, angle > tuning.idleReturnAngle {
                phase = .idle
                spring.reset(to: 0)
            }
        case .sealed:
            break  // only signalSleep, reset, or the unlock path leave sealed
        }
    }

    // MARK: - Output

    /// Spec section 9.1: the lid supplies the target, the spring supplies the
    /// output. Feed-forward is expressed in progress units per second so it is
    /// dimensionally consistent with `u`.
    private func publish(angle: Double, velocity: Double, dt: TimeInterval) -> FoldState {
        let span = tuning.foldStartAngle - tuning.foldEndAngle
        let u = min(max((tuning.foldStartAngle - angle) / span, 0), 1)
        let normalizedRate = -velocity / span            // progress units per second
        let target = min(max(u + tuning.feedForward * normalizedRate, 0), tuning.maxProgress)
        lastTarget = target

        switch phase {
        case .idle, .armed:
            spring.reset(to: 0)
            state = FoldState(phase: phase, progress: 0, velocity: 0)
        case .sealed:
            state = FoldState(phase: .sealed, progress: 1.0, velocity: 0)
        case .folding, .unfolding:
            spring.step(target: target, dt: dt)
            state = FoldState(
                phase: phase,
                progress: min(max(spring.value, 0), tuning.maxProgress),
                velocity: spring.velocity
            )
        }
        return state
    }

    /// Advances the spring toward the last computed target without a new angle
    /// sample. Two uses: the scripted unfold, which has no angle input at all,
    /// and rendering at a display rate higher than the 60 Hz sensor rate.
    @discardableResult
    public func tick(now: TimeInterval) -> FoldState {
        let dt = lastTimestamp.map { max(now - $0, 0) } ?? 0
        lastTimestamp = now
        guard dt > 0 else { return state }

        if let start = scriptedUnfoldStart {
            // The spring is deliberately bypassed here. Spec FR-10 wants a definite
            // 620 ms, and pushing a linear ramp through a 220/26 spring lags it by
            // rate * damping / stiffness, about 0.19 progress, which would stretch
            // the reveal past 900 ms and leave a visible tail. With no lid to track
            // there is nothing for the spring to buy, so drive the curve directly.
            let fraction = min(max((now - start) / tuning.scriptedUnfoldSeconds, 0), 1)
            let eased = fraction * fraction * (3 - 2 * fraction)   // smoothstep
            let progress = 1.0 - eased
            lastTarget = progress
            spring.reset(to: progress)   // keep spring state coherent for any later ingest
            if fraction >= 1 {
                scriptedUnfoldStart = nil
                phase = .idle
                spring.reset(to: 0)
                state = .idle
                return state
            }
            state = FoldState(
                phase: .unfolding,
                progress: progress,
                velocity: -6 * fraction * (1 - fraction) / tuning.scriptedUnfoldSeconds
            )
            return state
        }

        switch phase {
        case .folding, .unfolding:
            spring.step(target: lastTarget, dt: dt)
            state = FoldState(
                phase: phase,
                progress: min(max(spring.value, 0), tuning.maxProgress),
                velocity: spring.velocity
            )
        default:
            break
        }
        return state
    }

    /// Spec FR-10: after the session unlocks, unfold a freshly captured frame
    /// on a timed curve. The lid is already open, so there is no angle to
    /// track and `tick(now:)` drives this to completion.
    @discardableResult
    public func beginScriptedUnfold(now: TimeInterval) -> FoldState {
        phase = .unfolding
        scriptedUnfoldStart = now
        lastTimestamp = now
        spring.reset(to: 1.0)
        clearGate()
        state = FoldState(phase: .unfolding, progress: 1.0, velocity: 0)
        return state
    }
}
