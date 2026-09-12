import Foundation
import LidRippleCore
import LidRippleIntegration
import LidRippleSensor

/// The input implementation currently feeding the shared fold lifecycle.
public enum InputSourceMode: Equatable, Sendable {
    case sensor
    case timedFallback
    case unavailable
}

/// The event-only operations needed in addition to `LidAngleSource`.
///
/// Keeping these operations out of the core protocol means replay and HID
/// sources do not have to pretend they understand system close events.
public protocol FallbackAngleSource: LidAngleSource {
    func beginClose()
    func cancelTransition()
}

extension EventAngleSource: FallbackAngleSource {}

/// Owns exactly one HID or event-driven angle source and serializes replacement.
///
/// All mutations happen on the main actor. Source callbacks may originate on
/// arbitrary queues, so they hop to the main actor and pass through a generation
/// gate before reaching the application lifecycle.
@MainActor
public final class InputSourceController {
    public typealias HIDFactory = @MainActor (
        @escaping @Sendable () -> Void
    ) -> any LidAngleSource
    public typealias FallbackFactory = @MainActor () -> (any FallbackAngleSource)?
    public typealias SampleHandler = @MainActor @Sendable (AngleSample) -> Void
    public typealias ModeHandler = @MainActor @Sendable (InputSourceMode) -> Void

    public private(set) var mode: InputSourceMode = .unavailable
    public private(set) var isEnabled = false

    private let makeHID: HIDFactory
    private let makeFallback: FallbackFactory
    private let recovery: SensorRecovery
    private let recoverySleep: SensorRecovery.Sleeper
    private let onSample: SampleHandler
    private let onModeChanged: ModeHandler

    private var activeSource: (any LidAngleSource)?
    private var fallbackSource: (any FallbackAngleSource)?
    private var activeIngress: OrderedSampleIngress?
    private var sourceGeneration: UInt64 = 0
    private var issuedGeneration: UInt64 = 0
    private var recoveryGeneration: UInt64 = 0
    private var recoveryTask: Task<Void, Never>?
    private var sessionRestricted = false

    public convenience init(
        recovery: SensorRecovery = SensorRecovery(),
        onSample: @escaping SampleHandler,
        onModeChanged: @escaping ModeHandler = { _ in }
    ) {
        self.init(
            hidFactory: { unavailable in
                HIDAngleSource(serviceUnavailable: unavailable)
            },
            fallbackFactory: { try? EventAngleSource() },
            recovery: recovery,
            onSample: onSample,
            onModeChanged: onModeChanged
        )
    }

    public init(
        hidFactory: @escaping HIDFactory,
        fallbackFactory: @escaping FallbackFactory,
        recovery: SensorRecovery = SensorRecovery(),
        recoverySleep: @escaping SensorRecovery.Sleeper = {
            try await Task.sleep(for: $0)
        },
        onSample: @escaping SampleHandler,
        onModeChanged: @escaping ModeHandler = { _ in }
    ) {
        makeHID = hidFactory
        makeFallback = fallbackFactory
        self.recovery = recovery
        self.recoverySleep = recoverySleep
        self.onSample = onSample
        self.onModeChanged = onModeChanged
    }

    deinit {
        recoveryTask?.cancel()
        activeSource?.stop()
    }

    /// Selects HID first. An absent device or start failure selects fallback
    /// immediately, without consuming the runtime recovery budget.
    @discardableResult
    public func start() -> InputSourceMode {
        guard !isEnabled || activeSource == nil else { return mode }
        isEnabled = true
        cancelRecovery()
        deactivateSource()
        if !installHID() {
            _ = installFallback()
        }
        return mode
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) -> InputSourceMode {
        if enabled { return start() }
        stop()
        return mode
    }

    /// Stops input and invalidates all source and recovery callbacks.
    public func stop() {
        isEnabled = false
        cancelRecovery()
        deactivateSource()
        setMode(.unavailable)
    }

    /// Suppresses queued input while loginwindow or another user owns the
    /// session. In-progress fallback work is also cancelled so it owns no idle
    /// timer and cannot race the fresh scripted unfold on unlock.
    public func setSessionRestricted(_ restricted: Bool) {
        activeIngress?.setSuspended(restricted)
        sessionRestricted = restricted
        if restricted { fallbackSource?.cancelTransition() }
    }

    /// Starts the event-driven close program only when fallback owns input.
    /// This requires a safe pre-sleep signal; `willSleep` itself hard-seals
    /// immediately and is too late to run a visible transition reliably.
    @discardableResult
    public func beginFallbackClose() -> Bool {
        guard isEnabled,
              !sessionRestricted,
              mode == .timedFallback,
              let fallbackSource
        else { return false }
        activeIngress?.dropPending()
        fallbackSource.beginClose()
        return true
    }

    public func cancelFallbackTransition() {
        if fallbackSource != nil { activeIngress?.dropPending() }
        fallbackSource?.cancelTransition()
    }

    /// Re-runs the bounded HID policy (for wake or an explicit retry). A failed
    /// promotion restores fallback only after the final attempt.
    public func retryHID() {
        guard isEnabled else { return }
        beginRecovery()
    }

    /// Test/app-coordination seam for awaiting the currently scheduled bounded
    /// recovery without exposing its task.
    public func waitForRecovery() async {
        await recoveryTask?.value
    }

    private func installHID() -> Bool {
        guard isEnabled else { return false }

        // Keep the existing fallback alive through both probing and start().
        // A present device can still fail to open; promotion commits only once
        // the candidate has started successfully.
        let generation = allocateGeneration()
        let ingress = OrderedSampleIngress(isSuspended: sessionRestricted)
        let source = makeHID { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isEnabled,
                      self.sourceGeneration == generation,
                      self.mode == .sensor
                else { return }
                self.handleHIDUnavailable()
            }
        }

        guard source.isAvailable else {
            source.stop()
            return false
        }

        do {
            try source.start(makeSampleHandler(generation: generation, ingress: ingress))
        } catch {
            source.stop()
            return false
        }

        deactivateSource()
        sourceGeneration = generation
        activeSource = source
        activeIngress = ingress
        fallbackSource = nil
        setMode(.sensor)
        return true
    }

    @discardableResult
    private func installFallback() -> Bool {
        guard isEnabled else { return false }

        deactivateSource()
        let generation = allocateGeneration()
        let ingress = OrderedSampleIngress(isSuspended: sessionRestricted)
        guard let source = makeFallback(), source.isAvailable else {
            setMode(.unavailable)
            return false
        }

        do {
            try source.start(makeSampleHandler(generation: generation, ingress: ingress))
        } catch {
            source.stop()
            setMode(.unavailable)
            return false
        }

        sourceGeneration = generation
        activeSource = source
        activeIngress = ingress
        fallbackSource = source
        setMode(.timedFallback)
        return true
    }

    private func makeSampleHandler(
        generation: UInt64,
        ingress: OrderedSampleIngress
    ) -> @Sendable (AngleSample) -> Void {
        return { [weak self] sample in
            guard ingress.append(sample) else { return }
            if Thread.isMainThread {
                // Preserve synchronous delivery for fallback's first close
                // sample, but never overtake an older queued background sample.
                MainActor.assumeIsolated { [weak self] in
                    ingress.drain { self?.deliver($0, generation: generation) }
                }
            } else {
                Task { @MainActor [weak self] in
                    ingress.drain { self?.deliver($0, generation: generation) }
                }
            }
        }
    }

    private func deliver(_ sample: AngleSample, generation: UInt64) {
        guard isEnabled,
              !sessionRestricted,
              sourceGeneration == generation
        else { return }
        onSample(sample)
    }

    private func handleHIDUnavailable() {
        guard isEnabled, mode == .sensor else { return }
        deactivateSource()
        setMode(.unavailable)
        beginRecovery()
    }

    private func beginRecovery() {
        cancelRecovery()
        if mode == .timedFallback {
            // Waiting fallback owns no timer. Keep it available while the
            // bounded policy sleeps and probes; a successful HID start then
            // replaces it in one main-actor turn.
            fallbackSource?.cancelTransition()
            activeIngress?.dropPending()
        } else {
            deactivateSource()
            setMode(.unavailable)
        }
        recoveryGeneration &+= 1
        let generation = recoveryGeneration

        recoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let outcome = try await self.recovery.run(
                    attempt: { [weak self] in
                        guard let self,
                              self.isEnabled,
                              self.recoveryGeneration == generation
                        else { return false }
                        return self.installHID()
                    },
                    sleep: self.recoverySleep
                )
                guard self.isEnabled, self.recoveryGeneration == generation else { return }
                if case .fallbackRequired = outcome, self.mode != .timedFallback {
                    _ = self.installFallback()
                }
            } catch is CancellationError {
                return
            } catch {
                guard self.isEnabled, self.recoveryGeneration == generation else { return }
                _ = self.installFallback()
            }
            if self.recoveryGeneration == generation {
                self.recoveryTask = nil
            }
        }
    }

    private func cancelRecovery() {
        recoveryGeneration &+= 1
        recoveryTask?.cancel()
        recoveryTask = nil
    }

    private func deactivateSource() {
        sourceGeneration = 0
        activeIngress?.setSuspended(true)
        activeIngress = nil
        let source = activeSource
        activeSource = nil
        fallbackSource = nil
        source?.stop()
    }

    private func allocateGeneration() -> UInt64 {
        issuedGeneration &+= 1
        // Zero always denotes "no active source".
        if issuedGeneration == 0 { issuedGeneration &+= 1 }
        return issuedGeneration
    }

    private func setMode(_ newMode: InputSourceMode) {
        guard mode != newMode else { return }
        mode = newMode
        onModeChanged(newMode)
    }
}

/// A source can invoke its callback from different queues. One scheduled drain
/// per source preserves callback-enqueue order across the main-actor hop.
private final class OrderedSampleIngress: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [AngleSample] = []
    private var isDraining = false
    private var isSuspended: Bool

    init(isSuspended: Bool) {
        self.isSuspended = isSuspended
    }

    func setSuspended(_ suspended: Bool) {
        lock.lock()
        isSuspended = suspended
        if suspended {
            pending.removeAll()
            isDraining = false
        }
        lock.unlock()
    }

    func dropPending() {
        lock.lock()
        pending.removeAll()
        isDraining = false
        lock.unlock()
    }

    /// Returns true only for the caller responsible for starting the drain.
    func append(_ sample: AngleSample) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isSuspended else { return false }
        pending.append(sample)
        guard !isDraining else { return false }
        isDraining = true
        return true
    }

    @MainActor
    func drain(_ deliver: (AngleSample) -> Void) {
        while true {
            lock.lock()
            guard !pending.isEmpty else {
                isDraining = false
                lock.unlock()
                return
            }
            let sample = pending.removeFirst()
            lock.unlock()
            deliver(sample)
        }
    }
}
