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
    private var lastInputTimestamp: TimeInterval?

    /// Direction gate: tracks how long motion has been consistently one way
    /// and how far it has travelled. Both must clear before a direction
    /// commits (spec section 9.2 plus plan deviation 2).
    private var gateIsClosing = false
    private var gateSince: TimeInterval?
    private var gateStartAngle: Double?

    /// Set while a scripted (angle-free) unfold is running. Spec FR-10.
    private var scriptedUnfoldStart: TimeInterval?
    private var scriptedStartProgress: Double = 1
    private var scriptedOpeningFloor: Double?
    private var lastScriptedOpeningSampleTimestamp: TimeInterval?
    private var scriptedReleaseStart: TimeInterval?
    private var scriptedReleaseProgress: Double = 0
    private var lastTarget: Double = 0
    /// A physical seal can reverse in clamshell mode; a sleep/lock seal cannot
    /// consume angle input until the lifecycle explicitly resets or unlocks it.
    private var sealedBySystem = false

    public private(set) var state: FoldState = .idle
    public var openingFirstSampleWaitSeconds: Double { tuning.openingFirstSampleWaitSeconds }

    public init(tuning: FoldTuning = .default) {
        self.tuning = tuning
        self.filter = AngleFilter(tuning: tuning)
        self.spring = Spring(tuning: tuning)
    }

    @discardableResult
    public func ingest(_ sample: AngleSample) -> FoldState {
        // Validate before interrupting a reveal or touching the filter. The
        // input clock is separate from display ticks, which may arrive first.
        guard sample.degrees.isFinite, sample.timestamp.isFinite,
              lastInputTimestamp.map({ sample.timestamp > $0 }) ?? true
        else { return state }
        lastInputTimestamp = sample.timestamp
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
        // Input can arrive on the main actor after a display tick that has a
        // newer timestamp. Do not move the integration clock backwards: that
        // would make the next display frame take an oversized spring step.
        lastTimestamp = max(lastTimestamp ?? sample.timestamp, sample.timestamp)

        updateDirectionGate(angle: angle, velocity: velocity, now: sample.timestamp)
        advancePhase(angle: angle)
        return publish(angle: angle, velocity: velocity, dt: dt)
    }

    @discardableResult
    public func signalSleep() -> FoldState {
        phase = .sealed
        sealedBySystem = true
        spring.reset(to: 1.0)
        // Clear any in-flight scripted unfold: otherwise the next `tick(now:)`
        // would still take the `scriptedUnfoldStart` branch and drive `phase`
        // back out of `.sealed`, undoing the seal.
        scriptedUnfoldStart = nil
        scriptedStartProgress = 1
        scriptedOpeningFloor = nil
        lastScriptedOpeningSampleTimestamp = nil
        scriptedReleaseStart = nil
        state = FoldState(phase: .sealed, progress: 1.0, velocity: 0)
        return state
    }

    @discardableResult
    public func reset() -> FoldState {
        phase = .idle
        spring.reset(to: 0)
        filter = AngleFilter(tuning: tuning)
        lastTimestamp = nil
        lastInputTimestamp = nil
        clearGate()
        scriptedUnfoldStart = nil
        scriptedStartProgress = 1
        scriptedOpeningFloor = nil
        lastScriptedOpeningSampleTimestamp = nil
        scriptedReleaseStart = nil
        lastTarget = 0
        sealedBySystem = false
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
                sealedBySystem = false
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
            if !sealedBySystem,
               directionCommitted(closing: false, angle: angle, now: now) {
                phase = .unfolding
            }
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

    /// Advances the spring or post-unlock reveal at display cadence.
    @discardableResult
    public func tick(now: TimeInterval) -> FoldState {
        guard now.isFinite else { return state }
        let dt = lastTimestamp.map { max(now - $0, 0) } ?? 0
        lastTimestamp = max(lastTimestamp ?? now, now)
        guard dt > 0 else { return state }

        if let start = scriptedUnfoldStart {
            // The timed curve is a minimum reveal duration. On sensor-equipped
            // Macs, a measured lid angle is a floor on fold progress, so the
            // image cannot unfold faster than the lid. The spring is bypassed
            // to avoid adding an unwanted tail to either path.
            let fraction = min(max((now - start) / tuning.scriptedUnfoldSeconds, 0), 1)
            let eased = fraction * fraction * (3 - 2 * fraction)   // smoothstep
            // Fresh samples, even at a stationary angle, keep the measured
            // pose alive. Only an actual input stall starts the safety release.
            let lastPoseTime = max(start, lastScriptedOpeningSampleTimestamp ?? start)
            let elapsed = max(now - lastPoseTime, 0)
            let timeoutFade = now >= lastPoseTime + tuning.openingTrackHoldSeconds
                + tuning.scriptedUnfoldSeconds ? 0 : min(max(
                    (tuning.openingTrackHoldSeconds + tuning.scriptedUnfoldSeconds - elapsed)
                        / tuning.scriptedUnfoldSeconds, 0
                ), 1)
            let angleFloor = (scriptedOpeningFloor ?? 0) * timeoutFade
            let releaseFloor: Double
            if let releaseStart = scriptedReleaseStart {
                let releaseFraction = min(max(
                    (now - releaseStart) / tuning.scriptedUnfoldSeconds, 0
                ), 1)
                let releaseEased = releaseFraction * releaseFraction
                    * (3 - 2 * releaseFraction)
                releaseFloor = scriptedReleaseProgress * (1 - releaseEased)
            } else {
                releaseFloor = 0
            }
            // A delayed sample or 1° sensor jitter must never re-fold the image.
            // The angle floor is quantized in whole degrees on the observed M4;
            // ease each step over a few display frames. This filter approaches
            // the target from above, so it cannot outrun the physical lid.
            let target = min(state.progress, max(scriptedStartProgress * (1.0 - eased), angleFloor, releaseFloor))
            let progress: Double
            if scriptedOpeningFloor != nil, tuning.openingTrackSmoothingSeconds > 0 {
                let retention = exp(-dt / tuning.openingTrackSmoothingSeconds)
                progress = target + (state.progress - target) * retention
            } else {
                // No sensor: preserve the exact timed curve, including its end.
                progress = target
            }
            lastTarget = progress
            spring.reset(to: progress)   // keep spring state coherent for any later ingest
            if fraction >= 1, progress <= tuning.springSettleEpsilon {
                scriptedUnfoldStart = nil
                scriptedStartProgress = 1
                scriptedOpeningFloor = nil
                lastScriptedOpeningSampleTimestamp = nil
                scriptedReleaseStart = nil
                phase = .idle
                spring.reset(to: 0)
                state = .idle
                return state
            }
            state = FoldState(
                phase: .unfolding,
                progress: progress,
                velocity: (progress - state.progress) / dt
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

    /// After unlock, reveal only a freshly captured frame. Sensor samples can
    /// constrain this curve without entering the ordinary close-phase machine.
    @discardableResult
    public func beginScriptedUnfold(now: TimeInterval) -> FoldState {
        phase = .unfolding
        sealedBySystem = false
        scriptedUnfoldStart = now
        scriptedStartProgress = 1
        scriptedOpeningFloor = nil
        lastScriptedOpeningSampleTimestamp = nil
        scriptedReleaseStart = nil
        lastTimestamp = now
        spring.reset(to: 1.0)
        clearGate()
        state = FoldState(phase: .unfolding, progress: 1.0, velocity: 0)
        return state
    }

    /// The first reading after a fresh unlock places the still-hidden fold at
    /// the lid's actual pose. Starting at 1 here would visibly fold an already
    /// exposed desktop backwards when ScreenCaptureKit finishes late.
    @discardableResult
    public func alignScriptedOpening(_ sample: AngleSample) -> FoldState {
        guard scriptedUnfoldStart != nil,
              sample.degrees.isFinite, sample.timestamp.isFinite,
              sample.timestamp >= (lastScriptedOpeningSampleTimestamp ?? -.infinity)
        else { return state }
        trackScriptedOpening(sample)
        guard let floor = scriptedOpeningFloor else { return state }
        let progress = min(state.progress, floor)
        if progress <= tuning.springSettleEpsilon { return reset() }
        scriptedStartProgress = progress
        scriptedUnfoldStart = max(lastTimestamp ?? sample.timestamp, sample.timestamp)
        lastTimestamp = scriptedUnfoldStart
        spring.reset(to: progress)
        state = FoldState(phase: .unfolding, progress: progress, velocity: 0)
        return state
    }

    /// Constrain a post-unlock reveal to a physical opening lid. A fully open
    /// reading releases the constraint; absent samples preserve timed behavior.
    public func trackScriptedOpening(_ sample: AngleSample) {
        guard scriptedUnfoldStart != nil,
              sample.degrees.isFinite, sample.timestamp.isFinite,
              sample.timestamp >= (lastScriptedOpeningSampleTimestamp ?? -.infinity)
        else { return }
        lastScriptedOpeningSampleTimestamp = sample.timestamp
        let span = tuning.openingTrackEndAngle - tuning.sealAngle
        guard span > 0 else { return }
        let floor = min(max((tuning.openingTrackEndAngle - sample.degrees) / span, 0), 1)
        scriptedOpeningFloor = min(scriptedOpeningFloor ?? 1, floor)
    }

    /// A sensor loss must not leave the overlay waiting for a lid reading.
    public func clearScriptedOpeningTracking() {
        if scriptedUnfoldStart != nil, scriptedOpeningFloor != nil {
            scriptedReleaseStart = lastTimestamp
            scriptedReleaseProgress = state.progress
        }
        scriptedOpeningFloor = nil
        lastScriptedOpeningSampleTimestamp = nil
    }
}
