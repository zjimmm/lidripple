import CoreGraphics
import Foundation
import LidRippleCapture
import LidRippleCore
import OSLog

/// Serializes the sensor -> driver -> capture -> overlay path and owns every
/// lifecycle escape hatch that can invalidate an in-flight capture.
@MainActor
public final class FoldLifecycleCoordinator {
    private let wakeLog = Logger(subsystem: "com.lidripple.app", category: "wake")
    public typealias DisplayIDProvider = @MainActor () -> CGDirectDisplayID?

    public private(set) var state: FoldState
    public var availability: FoldLifecycleAvailability {
        guard isEnabled else { return .disabled }
        switch sessionAccess {
        case .locked: return .locked
        case .inactive: return .sessionInactive
        case .active: break
        }
        guard displayAvailable else { return .displayUnavailable }
        guard inputAvailability != .unavailable else { return .inputUnavailable }
        return .active
    }
    public private(set) var lastCaptureErrorDescription: String?
    public private(set) var usesFallbackReveal = false
    public private(set) var reducedQuality = false
    public private(set) var captureActivity: FoldCaptureActivity = .idle
    public private(set) var overlayVisible = false
    public private(set) var inputAvailability: FoldInputAvailability = .sensor

    public var diagnostics: FoldRuntimeDiagnostics {
        FoldRuntimeDiagnostics(
            state: state,
            availability: availability,
            hasInstalledFrame: frameInstalled,
            requiresScriptedUnfold: requiresScriptedUnfold,
            usesFallbackReveal: usesFallbackReveal,
            reducedQuality: reducedQuality,
            captureActivity: captureActivity,
            overlayVisible: overlayVisible,
            inputAvailability: inputAvailability,
            builtInDisplayAvailable: displayAvailable,
            sessionRestricted: sessionAccess != .active,
            lastCaptureErrorDescription: lastCaptureErrorDescription
        )
    }

    private let driver: FoldDriver
    private let capture: any FoldCapturing
    private weak var output: (any FoldLifecycleOutput)?
    private let displayID: DisplayIDProvider

    private var generation: UInt64 = 0
    private var captureTask: Task<Void, Never>?
    private var frameInstalled = false
    private var requiresScriptedUnfold = false
    private var hasLoggedOpeningSample = false
    private var awaitingFirstOpeningSample = false
    private var firstOpeningSampleDeadline: TimeInterval?
    private var targetDisplayID: CGDirectDisplayID?
    private var isEnabled = true
    private var sessionAccess: SessionAccess = .active
    private var displayAvailable = false

    public init(
        driver: FoldDriver = FoldDriver(),
        capture: any FoldCapturing,
        output: any FoldLifecycleOutput,
        displayID: @escaping DisplayIDProvider
    ) {
        self.driver = driver
        self.capture = capture
        self.output = output
        self.displayID = displayID
        state = driver.state
        targetDisplayID = displayID()
        displayAvailable = targetDisplayID != nil
    }

    deinit {
        captureTask?.cancel()
    }

    /// Processes one physical sensor sample. Capture work is deliberately
    /// asynchronous so a slow ScreenCaptureKit startup cannot stall the 60 Hz
    /// driver or reorder input samples on the main actor.
    @discardableResult
    public func ingest(_ sample: AngleSample) -> FoldState {
        guard isEnabled,
              sessionAccess == .active,
              displayAvailable,
              inputAvailability != .unavailable
        else { return state }

        if requiresScriptedUnfold {
            if inputAvailability == .sensor {
                if awaitingFirstOpeningSample, sample.degrees.isFinite,
                   sample.timestamp.isFinite {
                    let previous = state.phase
                    state = driver.alignScriptedOpening(sample)
                    awaitingFirstOpeningSample = false
                    firstOpeningSampleDeadline = nil
                    if state.phase == .idle {
                        applyTransition(from: previous, to: state, renderActive: false)
                    } else if frameInstalled {
                        output?.update(state)
                        overlayVisible = true
                        wakeLog.notice("freshUnfold overlayShown firstAngle=\(sample.degrees)")
                    }
                } else {
                    driver.trackScriptedOpening(sample)
                }
                if !hasLoggedOpeningSample, sample.degrees.isFinite {
                    hasLoggedOpeningSample = true
                    wakeLog.notice("freshUnfold sensorPacing firstAngle=\(sample.degrees)")
                }
            }
            return state
        }

        let previous = state.phase
        state = driver.ingest(sample)
        applyTransition(from: previous, to: state, renderActive: false)
        return state
    }

    /// Advances spring or scripted-unfold animation at display cadence.
    @discardableResult
    public func tick(now: TimeInterval) -> FoldState {
        guard isEnabled, sessionAccess == .active, displayAvailable else { return state }
        if awaitingFirstOpeningSample,
           let deadline = firstOpeningSampleDeadline, now >= deadline {
            awaitingFirstOpeningSample = false
            firstOpeningSampleDeadline = nil
            wakeLog.notice("freshUnfold firstAngleTimedOut")
        }
        let previous = state.phase
        state = driver.tick(now: now)
        applyTransition(from: previous, to: state, renderActive: true)
        return state
    }

    /// Sleep is a hard seal. It draws that terminal state once, then immediately
    /// invalidates capture and clears/hides the GPU source; it is never reused
    /// after wake.
    @discardableResult
    public func systemWillSleep() -> FoldState {
        guard isEnabled else { return state }
        requiresScriptedUnfold = true
        state = driver.signalSleep()
        if frameInstalled { output?.update(state) }
        invalidateCapture(clearOutput: true, hide: true)
        return state
    }

    /// Drawing above loginwindow is forbidden. Any physical motion while locked
    /// is ignored and the next unlock is routed through a fresh capture.
    @discardableResult
    public func sessionLocked() -> FoldState {
        sessionAccess = .locked
        requiresScriptedUnfold = true
        state = driver.signalSleep()
        invalidateCapture(clearOutput: true, hide: true)
        return state
    }

    /// Captures the post-unlock desktop before revealing it. If permission or
    /// capture fails, an in-memory warm-black source fades away instead; a stale
    /// pre-lock texture is never displayed.
    @discardableResult
    public func sessionUnlocked(
        firstFrameTimeout: TimeInterval = 0.5,
        now: @MainActor () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) async -> FoldState {
        guard isEnabled,
              sessionAccess == .locked || (sessionAccess == .active && requiresScriptedUnfold)
        else { return state }

        wakeLog.notice("freshUnfold begin")

        sessionAccess = .active
        let cycle = beginNewCycle(clearOutput: true, hide: true)

        do {
            await capture.reset()
            guard isCurrent(cycle) else { return state }
            guard let display = displayID(),
                  let output,
                  output.reconfigureForBuiltInDisplay()
            else {
                displayAvailable = false
                state = driver.signalSleep()
                return state
            }
            targetDisplayID = display
            displayAvailable = true
            captureActivity = .warming
            try await capture.warm(
                displayID: display,
                excludingWindowID: output.captureExclusionWindowID
            )
            guard isCurrent(cycle) else { return state }
            captureActivity = .freezing
            let frame = try await capture.freeze(waitingUpTo: firstFrameTimeout)
            guard isCurrent(cycle) else { return state }
            try output.setSource(frame)
            wakeLog.notice("freshUnfold capturedFrameInstalled")
            frameInstalled = true
            captureActivity = .frozen
            usesFallbackReveal = false
            lastCaptureErrorDescription = nil
        } catch {
            guard isCurrent(cycle) else { return state }
            wakeLog.error("freshUnfold captureFailed type=\(String(describing: type(of: error)), privacy: .public)")
            lastCaptureErrorDescription = String(describing: error)
            do {
                try output?.setFallbackSource()
                frameInstalled = true
                captureActivity = .idle
                usesFallbackReveal = true
            } catch {
                lastCaptureErrorDescription = String(describing: error)
                frameInstalled = false
                captureActivity = .idle
                output?.hide()
            }
            await capture.reset()
            guard isCurrent(cycle) else { return state }
        }

        hasLoggedOpeningSample = false
        let revealStart = now()
        state = driver.beginScriptedUnfold(now: revealStart)
        awaitingFirstOpeningSample = frameInstalled && !usesFallbackReveal
            && inputAvailability == .sensor
        firstOpeningSampleDeadline = awaitingFirstOpeningSample
            ? revealStart + driver.openingFirstSampleWaitSeconds : nil
        if frameInstalled && !awaitingFirstOpeningSample {
            output?.update(state)
            overlayVisible = true
            wakeLog.notice("freshUnfold overlayShown fallback=\(self.usesFallbackReveal)")
        } else if !frameInstalled {
            wakeLog.error("freshUnfold noFrame")
        }
        return state
    }

    /// A display geometry change aborts an active fold through `sealed`, then
    /// retargets the sole window. With no built-in display the controller stays
    /// inert until a later reconfiguration succeeds.
    @discardableResult
    public func displayConfigurationChanged() -> FoldState {
        guard let candidate = displayID() else {
            abortForDisplayLoss(nextDisplayID: nil)
            return state
        }

        guard candidate == targetDisplayID else {
            abortForDisplayLoss(nextDisplayID: candidate)
            if output?.reconfigureForBuiltInDisplay() == true {
                displayAvailable = true
                if isEnabled, sessionAccess == .active, !requiresScriptedUnfold {
                    state = driver.reset()
                    output?.update(state)
                }
            }
            return state
        }

        guard output?.reconfigureForBuiltInDisplay() == true else {
            abortForDisplayLoss(nextDisplayID: candidate)
            return state
        }

        if !displayAvailable {
            displayAvailable = true
            if isEnabled, sessionAccess == .active, !requiresScriptedUnfold {
                state = driver.reset()
                output?.update(state)
            }
        } else if frameInstalled {
            output?.update(state)
            overlayVisible = state.phase == .folding
                || state.phase == .unfolding
                || state.phase == .sealed
        }
        return state
    }

    private func abortForDisplayLoss(nextDisplayID: CGDirectDisplayID?) {
        if state.phase == .folding || state.phase == .unfolding || state.phase == .sealed {
            state = driver.signalSleep()
            if frameInstalled { output?.update(state) }
        } else {
            state = driver.reset()
        }
        invalidateCapture(clearOutput: true, hide: true)
        targetDisplayID = nextDisplayID
        displayAvailable = false
    }

    /// Fast user switching must not leave a capture or overlay owned by the old
    /// console session.
    @discardableResult
    public func sessionResignedActive() -> FoldState {
        sessionAccess = .inactive
        requiresScriptedUnfold = false
        state = driver.reset()
        invalidateCapture(clearOutput: true, hide: true)
        return state
    }

    @discardableResult
    public func sessionBecameActive() -> FoldState {
        guard sessionAccess == .inactive else { return state }
        sessionAccess = .active
        state = driver.reset()
        return state
    }

    /// M3 exposes the fallback handoff; M5 binds EventAngleSource to it.
    @discardableResult
    public func sensorUnavailable() -> FoldState {
        setInputAvailability(.unavailable)
    }

    @discardableResult
    public func sensorRecovered() -> FoldState {
        setInputAvailability(.sensor)
    }

    /// Records the active M5 input implementation independently of user,
    /// session, display, permission, and capture state. Only `.unavailable`
    /// disables ingestion; sensor and timed fallback share the same driver.
    @discardableResult
    public func setInputAvailability(_ availability: FoldInputAvailability) -> FoldState {
        let wasAvailable = inputAvailability != .unavailable
        inputAvailability = availability
        if availability != .sensor {
            if awaitingFirstOpeningSample {
                awaitingFirstOpeningSample = false
                firstOpeningSampleDeadline = nil
                if frameInstalled, state.phase == .unfolding {
                    output?.update(state)
                    overlayVisible = true
                }
            }
            driver.clearScriptedOpeningTracking()
        }
        if availability == .unavailable,
           wasAvailable,
           isEnabled,
           sessionAccess == .active,
           !requiresScriptedUnfold {
            state = driver.reset()
            invalidateCapture(clearOutput: true, hide: true)
        }
        return state
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) -> FoldState {
        if enabled {
            guard !isEnabled else { return state }
            isEnabled = true
            if sessionAccess == .active, displayAvailable {
                state = driver.reset()
            }
        } else {
            isEnabled = false
            requiresScriptedUnfold = false
            state = driver.reset()
            invalidateCapture(clearOutput: true, hide: true)
        }
        return state
    }

    public func setReducedQuality(_ reduced: Bool) {
        reducedQuality = reduced
        output?.setReducedQuality(reduced)
    }

    /// Live presentation tuning. This does not reconstruct the driver, change
    /// its thresholds/timing, or interact with capture/overlay visibility.
    public func setTuning(_ tuning: FoldTuning) {
        output?.setTuning(tuning)
    }

    public func shutdown() async {
        isEnabled = false
        requiresScriptedUnfold = false
        state = driver.reset()
        generation &+= 1
        captureTask?.cancel()
        captureTask = nil
        output?.clearSource()
        output?.hide()
        frameInstalled = false
        awaitingFirstOpeningSample = false
        firstOpeningSampleDeadline = nil
        captureActivity = .idle
        overlayVisible = false
        await capture.reset()
    }

    /// Test/diagnostic synchronization point for phase-triggered capture work.
    public func waitForPendingCapture() async {
        await captureTask?.value
    }

    private func applyTransition(
        from previous: FoldPhase,
        to next: FoldState,
        renderActive: Bool
    ) {
        switch next.phase {
        case .idle:
            if previous == .unfolding, requiresScriptedUnfold {
                wakeLog.notice("freshUnfold completed")
            }
            requiresScriptedUnfold = false
            if previous != .idle {
                output?.update(next)
                overlayVisible = false
                invalidateCapture(clearOutput: true, hide: true)
            }

        case .armed:
            if previous != .armed { beginWarmCapture() }

        case .folding:
            if previous == .armed { freezeWarmCapture() }
            if frameInstalled, renderActive {
                output?.update(next)
                overlayVisible = true
            }

        case .unfolding:
            if frameInstalled, renderActive, !awaitingFirstOpeningSample {
                output?.update(next)
                overlayVisible = true
            }

        case .sealed:
            if frameInstalled {
                output?.update(next)
                overlayVisible = true
            }
        }
    }

    private func beginWarmCapture() {
        guard let display = displayID(), let output else {
            displayAvailable = false
            return
        }

        let cycle = beginNewCycle(clearOutput: true, hide: true)
        let capture = self.capture
        let excludedWindow = output.captureExclusionWindowID
        captureActivity = .warming
        captureTask = Task { [weak self] in
            await capture.reset()
            guard let self, self.isCurrent(cycle) else { return }
            do {
                try await capture.warm(
                    displayID: display,
                    excludingWindowID: excludedWindow
                )
            } catch {
                guard self.isCurrent(cycle) else { return }
                self.lastCaptureErrorDescription = String(describing: error)
                self.captureActivity = .idle
            }
        }
    }

    private func freezeWarmCapture() {
        let warmTask = captureTask
        let cycle = generation
        let capture = self.capture
        captureActivity = .freezing
        captureTask = Task { [weak self] in
            await warmTask?.value
            guard let self, self.isCurrent(cycle) else { return }
            do {
                let frame = try await capture.freeze(waitingUpTo: 0.1)
                guard self.isCurrent(cycle), let output = self.output else { return }
                try output.setSource(frame)
                self.frameInstalled = true
                self.captureActivity = .frozen
                self.usesFallbackReveal = false
                self.lastCaptureErrorDescription = nil
                output.update(self.state)
                self.overlayVisible = true
            } catch {
                guard self.isCurrent(cycle) else { return }
                self.lastCaptureErrorDescription = String(describing: error)
                self.captureActivity = .idle
                await capture.reset()
            }
        }
    }

    @discardableResult
    private func beginNewCycle(clearOutput: Bool, hide: Bool) -> UInt64 {
        generation &+= 1
        captureTask?.cancel()
        captureTask = nil
        frameInstalled = false
        awaitingFirstOpeningSample = false
        firstOpeningSampleDeadline = nil
        captureActivity = .idle
        usesFallbackReveal = false
        if clearOutput { output?.clearSource() }
        if hide { output?.hide() }
        if hide { overlayVisible = false }
        return generation
    }

    private func invalidateCapture(clearOutput: Bool, hide: Bool) {
        let capture = self.capture
        _ = beginNewCycle(clearOutput: clearOutput, hide: hide)
        captureTask = Task { await capture.reset() }
    }

    private func isCurrent(_ cycle: UInt64) -> Bool {
        generation == cycle && !Task.isCancelled
    }
}

private enum SessionAccess {
    case active
    case locked
    case inactive
}
