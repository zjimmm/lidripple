import AppKit
import CoreGraphics
import Foundation
import LidRippleCapture
import LidRippleCore
import LidRippleIntegration
import LidRippleOverlay
import LidRippleSensor

/// The lifecycle surface composed by the menu-bar application. Keeping this
/// interface separate from the concrete coordinator lets policy tests prove
/// ordering without constructing ScreenCaptureKit or a window.
@MainActor
public protocol AppLifecycleControlling: AnyObject {
    var state: FoldState { get }

    @discardableResult func ingest(_ sample: AngleSample) -> FoldState
    @discardableResult func tick(now: TimeInterval) -> FoldState
    @discardableResult func systemWillSleep() -> FoldState
    @discardableResult func sessionLocked() -> FoldState
    @discardableResult func sessionUnlocked(
        firstFrameTimeout: TimeInterval,
        now: @MainActor () -> TimeInterval
    ) async -> FoldState
    @discardableResult func sessionResignedActive() -> FoldState
    @discardableResult func sessionBecameActive() -> FoldState
    @discardableResult func displayConfigurationChanged() -> FoldState
    @discardableResult func sensorUnavailable() -> FoldState
    @discardableResult func sensorRecovered() -> FoldState
    @discardableResult func setInputAvailability(_ availability: FoldInputAvailability) -> FoldState
    @discardableResult func setEnabled(_ enabled: Bool) -> FoldState
    func setReducedQuality(_ reduced: Bool)
    func setTuning(_ tuning: FoldTuning)
    func waitForPendingCapture() async
    func shutdown() async
}

extension FoldLifecycleCoordinator: AppLifecycleControlling {}

@MainActor
public protocol AppInputSourceControlling: AnyObject {
    var mode: InputSourceMode { get }
    var isEnabled: Bool { get }

    @discardableResult func start() -> InputSourceMode
    @discardableResult func setEnabled(_ enabled: Bool) -> InputSourceMode
    func stop()
    func setSessionRestricted(_ restricted: Bool)
    @discardableResult func beginFallbackClose() -> Bool
    func cancelFallbackTransition()
    func retryHID()
    func waitForRecovery() async
}

extension InputSourceController: AppInputSourceControlling {}

@MainActor
public protocol AppDebugPresenting: AnyObject {
    func beginDebugPreview(tuning: FoldTuning) throws
    func updateDebugPreview(progress: Double, direction: Double)
    func endDebugPreview()
    func setTuning(_ tuning: FoldTuning)
}

extension OverlayPresenter: AppDebugPresenting {}

@MainActor
public protocol AppAnimationCancellation: AnyObject {
    func cancel()
}

@MainActor
public protocol AppAnimationScheduling: AnyObject {
    func schedule(
        interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any AppAnimationCancellation
}

@MainActor
public final class RunLoopAppAnimationScheduler: AppAnimationScheduling {
    public init() {}

    public func schedule(
        interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any AppAnimationCancellation {
        let cancellation = TimerAnimationCancellation()
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { action() }
        }
        cancellation.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        return cancellation
    }
}

@MainActor
private final class TimerAnimationCancellation: AppAnimationCancellation {
    var timer: Timer?

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

public enum AppCoordinatorConstructionError: Error, Equatable {
    case noBuiltInDisplayOrMetalRenderer
    case captureUnavailable(String)
}

/// Owns product policy around the single M3 lifecycle, capture pipeline, input
/// source, and overlay. AppDelegate only translates operating-system events.
@MainActor
public final class AppCoordinator: DebugScrubberSession {
    public typealias InputFactory = @MainActor (
        @escaping InputSourceController.SampleHandler,
        @escaping InputSourceController.ModeHandler
    ) -> any AppInputSourceControlling

    public private(set) var menuController: MenuBarController!
    public private(set) var inputMode: InputSourceMode = .unavailable
    public private(set) var isStarted = false
    public private(set) var isDebugging = false

    private let preferences: AppPreferences
    private let lifecycle: any AppLifecycleControlling
    private let permission: ScreenRecordingPermissionController
    private let onboarding: any ScreenRecordingOnboardingPresenting
    private let launchAtLogin: LaunchAtLoginController
    private let debugPresenter: any AppDebugPresenting
    private let urlOpener: any ExternalURLOpening
    private let animationScheduler: any AppAnimationScheduling
    private let now: @MainActor () -> TimeInterval
    private let sessionAccessNow: @MainActor () -> ConsoleSessionAccess
    private let isCurrentConsoleNow: @MainActor () -> Bool
    private let terminateApplication: @MainActor () -> Void
    private let reportError: @MainActor (String) -> Void
    /// Retains the production lifecycle output, which M3 intentionally holds
    /// weakly to make teardown unambiguous.
    private let runtimeAnchor: AnyObject?

    private var inputSource: (any AppInputSourceControlling)!
    private var debugScrubber: DebugScrubberController!
    private var animation: (any AppAnimationCancellation)?
    private var sessionRestricted = false
    private var isTerminating = false
    private var hasAppliedInputMode = false
    private var debugSessionGeneration: UInt64 = 0
    private var isUnlocking = false
    private var pendingExplicitUnlock = false

    public init(
        preferences: AppPreferences,
        lifecycle: any AppLifecycleControlling,
        permission: ScreenRecordingPermissionController,
        onboarding: any ScreenRecordingOnboardingPresenting,
        launchAtLogin: LaunchAtLoginController,
        debugPresenter: any AppDebugPresenting,
        urlOpener: any ExternalURLOpening,
        inputFactory: @escaping InputFactory,
        animationScheduler: any AppAnimationScheduling = RunLoopAppAnimationScheduler(),
        debugScheduler: (any DebugPlaybackScheduling)? = nil,
        presentsMenu: Bool = true,
        presentsDebugPanel: Bool = true,
        now: @escaping @MainActor () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        sessionAccessNow: @escaping @MainActor () -> ConsoleSessionAccess = {
            guard let values = CGSessionCopyCurrentDictionary() as? [String: Any] else {
                return .unknown
            }
            return .resolve(
                onConsole: values["kCGSSessionOnConsoleKey"] as? Bool,
                screenLocked: values["CGSSessionScreenIsLocked"] as? Bool
            )
        },
        isCurrentConsoleNow: @escaping @MainActor () -> Bool = {
            guard let values = CGSessionCopyCurrentDictionary() as? [String: Any] else {
                return false
            }
            return values["kCGSSessionOnConsoleKey"] as? Bool == true
        },
        terminateApplication: @escaping @MainActor () -> Void = {
            NSApplication.shared.terminate(nil)
        },
        reportError: @escaping @MainActor (String) -> Void = { _ in },
        runtimeAnchor: AnyObject? = nil
    ) {
        self.preferences = preferences
        self.lifecycle = lifecycle
        self.permission = permission
        self.onboarding = onboarding
        self.launchAtLogin = launchAtLogin
        self.debugPresenter = debugPresenter
        self.urlOpener = urlOpener
        self.animationScheduler = animationScheduler
        self.now = now
        self.sessionAccessNow = sessionAccessNow
        self.isCurrentConsoleNow = isCurrentConsoleNow
        self.terminateApplication = terminateApplication
        self.reportError = reportError
        self.runtimeAnchor = runtimeAnchor

        inputSource = inputFactory(
            { [weak self] sample in self?.receive(sample) },
            { [weak self] mode in self?.sourceModeChanged(mode) }
        )
        debugScrubber = DebugScrubberController(
            session: self,
            scheduler: debugScheduler,
            presentsPanel: presentsDebugPanel,
            reportError: reportError
        )
        menuController = MenuBarController(
            snapshot: makeSnapshot(),
            actions: makeMenuActions(),
            installStatusItem: presentsMenu
        )
    }

    /// Constructs the real one-capture/one-overlay application graph.
    public static func production(
        preferences: AppPreferences = AppPreferences(),
        urlOpener: (any ExternalURLOpening)? = nil,
        terminateApplication: @escaping @MainActor () -> Void = {
            NSApplication.shared.terminate(nil)
        },
        reportError: @escaping @MainActor (String) -> Void = { _ in }
    ) throws -> AppCoordinator {
        guard let presenter = OverlayPresenter() else {
            throw AppCoordinatorConstructionError.noBuiltInDisplayOrMetalRenderer
        }

        let capture: CaptureCoordinator
        do {
            capture = try CaptureCoordinator()
        } catch {
            throw AppCoordinatorConstructionError.captureUnavailable(String(describing: error))
        }

        let opener = urlOpener ?? WorkspaceURLOpener()
        let output = ProductionOverlayLifecycleOutput(presenter: presenter)
        let lifecycle = FoldLifecycleCoordinator(
            capture: capture,
            output: output,
            displayID: { BuiltInDisplay.displayID() }
        )
        let permission = ScreenRecordingPermissionController(
            preferences: preferences,
            urlOpener: opener
        )
        let login = LaunchAtLoginController(
            preferences: preferences,
            urlOpener: opener
        )

        return AppCoordinator(
            preferences: preferences,
            lifecycle: lifecycle,
            permission: permission,
            onboarding: NativeScreenRecordingOnboardingPresenter(),
            launchAtLogin: login,
            debugPresenter: presenter,
            urlOpener: opener,
            inputFactory: { onSample, onModeChanged in
                InputSourceController(onSample: onSample, onModeChanged: onModeChanged)
            },
            terminateApplication: terminateApplication,
            reportError: reportError,
            runtimeAnchor: output
        )
    }

    /// Starts once, performs first-run onboarding, and leaves the runtime inert
    /// unless both the user preference and Screen Recording grant permit it.
    public func start(sessionAccess: ConsoleSessionAccess) {
        guard !isStarted, !isTerminating else { return }
        isStarted = true
        lifecycle.setTuning(currentTuning)
        _ = launchAtLogin.refresh()
        sessionRestricted = sessionAccess != .active || sessionAccessNow() != .active
        inputSource.setSessionRestricted(sessionRestricted)
        if sessionRestricted { _ = lifecycle.sessionLocked() }
        runOnboardingIfEligible()
        if !sessionRestricted, sessionAccessNow() != .active {
            restrictSession(lockLifecycle: true)
        }
        applyRuntimePolicy()
        refreshMenu()
    }

    public func setEnabled(_ enabled: Bool) {
        preferences.isEnabled = enabled
        if !enabled {
            stopAnimation()
            inputSource.stop()
            if !isDebugging { _ = lifecycle.setEnabled(false) }
        } else if !isDebugging {
            runOnboardingIfEligible()
            applyRuntimePolicy()
        }
        refreshMenu()
    }

    public func setIntensity(_ intensity: Double) {
        preferences.intensity = intensity
        lifecycle.setTuning(currentTuning)
        if isDebugging { debugPresenter.setTuning(currentTuning) }
        refreshMenu()
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        let state = launchAtLogin.setEnabled(enabled)
        if let error = launchAtLogin.lastErrorDescription {
            reportError("Unable to change Launch at Login: \(error)")
        }
        menuController.updateLaunchAtLogin(state)
    }

    public func openLaunchAtLoginSettings() {
        guard launchAtLogin.openSettings() else {
            reportError("Unable to open Login Items settings.")
            return
        }
    }

    public func screenRecordingAction() {
        guard !sessionRestricted, sessionAccessNow() == .active else { return }
        let state: ScreenRecordingPermissionState
        switch permission.state {
        case .granted:
            state = .granted
        case .notDetermined:
            if preferences.screenRecordingOnboardingCompleted {
                state = permission.requestAfterExplanation()
            } else {
                state = permission.runFirstLaunchOnboardingIfNeeded(
                    enabled: true,
                    presenter: onboarding
                )
            }
        case .denied:
            guard permission.openSettings() else {
                reportError("Unable to open Screen Recording settings.")
                return
            }
            state = .denied
        }
        if state == .granted { applyRuntimePolicy() }
        refreshMenu()
    }

    /// Refreshes TCC and login-item truth after returning from System Settings.
    public func applicationDidBecomeActive() {
        let previousPermission = permission.state
        let currentPermission = permission.refresh()
        _ = launchAtLogin.refresh()
        if currentPermission != previousPermission, !isDebugging { applyRuntimePolicy() }
        refreshMenu()
    }

    public func openDebugScrubber() {
        guard isStarted, !isTerminating, !sessionRestricted,
              sessionAccessNow() == .active else { return }
        let generation = debugSessionGeneration
        Task { @MainActor [weak self] in
            guard let self, generation == self.debugSessionGeneration,
                  !self.sessionRestricted, !self.isTerminating else { return }
            await self.debugScrubber.open(intensity: self.preferences.intensity)
        }
    }

    /// When the private lock-state key is absent, startup must fail closed.
    /// Opening this user's own status menu proves the desktop is interactive
    /// without granting an unknown background session capture authority.
    public func menuDidOpen() {
        guard isStarted, !isTerminating, sessionRestricted,
              sessionAccessNow() == .unknown,
              isCurrentConsoleNow() else { return }
        Task { @MainActor [weak self] in
            await self?.unlockAndRestoreRuntime(explicitUnlock: true)
        }
    }

    public func setReducedQuality(_ reduced: Bool) {
        lifecycle.setReducedQuality(reduced)
    }

    /// The system can suspend immediately after this notification. Hard-seal
    /// and invalidate capture synchronously; a visible sensor-less close needs
    /// an earlier public event and remains an S7 physical-device acceptance gate.
    public func systemWillSleep() {
        guard isStarted, !isTerminating else { return }
        abortDebugForRestriction()
        // WindowServer can suspend before a deferred timer fires. Preserve the
        // M3 hard-seal contract and never carry a capture stream across sleep.
        finalizeSleep()
    }

    public func systemDidWake(sessionAccess: ConsoleSessionAccess) async {
        inputSource.cancelFallbackTransition()
        guard sessionAccess == .active, sessionAccessNow() == .active else {
            restrictSession(lockLifecycle: true)
            refreshMenu()
            return
        }
        await unlockAndRestoreRuntime()
        retryHIDAfterWakeIfNeeded()
    }

    public func screenDidLock() {
        abortDebugForRestriction()
        stopAnimation()
        sessionRestricted = true
        inputSource.setSessionRestricted(true)
        inputSource.stop()
        _ = lifecycle.sessionLocked()
        sourceModeChanged(.unavailable)
        refreshMenu()
    }

    public func screenDidUnlock(
        sessionAccess: ConsoleSessionAccess,
        onConsole: Bool
    ) async {
        // This explicit unlock signal can authorize the public on-console
        // evidence when macOS omits its private lock-state dictionary key.
        guard onConsole, sessionAccess != .restricted,
              isExplicitUnlockAuthorizedNow() else {
            restrictSession(lockLifecycle: true)
            refreshMenu()
            return
        }
        if isUnlocking {
            pendingExplicitUnlock = true
            return
        }
        await unlockAndRestoreRuntime(explicitUnlock: true)
        retryHIDAfterWakeIfNeeded()
    }

    public func sessionResignedActive() {
        abortDebugForRestriction()
        stopAnimation()
        sessionRestricted = true
        inputSource.setSessionRestricted(true)
        inputSource.stop()
        _ = lifecycle.sessionResignedActive()
        sourceModeChanged(.unavailable)
        refreshMenu()
    }

    public func sessionBecameActive(sessionAccess: ConsoleSessionAccess) {
        guard isStarted, !isTerminating else { return }
        guard sessionAccess == .active, sessionAccessNow() == .active else {
            restrictSession(lockLifecycle: true)
            refreshMenu()
            return
        }
        sessionRestricted = false
        _ = lifecycle.sessionBecameActive()
        inputSource.setSessionRestricted(false)
        runOnboardingIfEligible()
        applyRuntimePolicy()
        refreshMenu()
    }

    public func displayConfigurationChanged() {
        let state = lifecycle.displayConfigurationChanged()
        updateAnimation(for: state)
    }

    public func shutdown() async {
        guard !isTerminating else { return }
        isTerminating = true
        stopAnimation()
        inputSource.stop()
        debugSessionGeneration &+= 1
        debugScrubber.abortForSystemRestriction()
        debugPresenter.endDebugPreview()
        isDebugging = false
        menuController.uninstall()
        await lifecycle.shutdown()
    }

    // MARK: DebugScrubberSession

    public func prepareDebugSession(intensity: Double) async throws {
        guard isStarted, !isTerminating, !sessionRestricted,
              sessionAccessNow() == .active else { throw CancellationError() }
        debugSessionGeneration &+= 1
        let generation = debugSessionGeneration
        isDebugging = true
        stopAnimation()
        inputSource.stop()
        _ = lifecycle.setEnabled(false)
        await lifecycle.waitForPendingCapture()
        guard generation == debugSessionGeneration, !isTerminating,
              !sessionRestricted, sessionAccessNow() == .active else {
            throw CancellationError()
        }
        do {
            try debugPresenter.beginDebugPreview(
                tuning: FoldTuning.default.withIntensity(intensity)
            )
            refreshMenu()
        } catch {
            isDebugging = false
            applyRuntimePolicy()
            refreshMenu()
            throw error
        }
    }

    public func updateDebugProgress(_ progress: Double, direction: Double) {
        guard isDebugging else { return }
        debugPresenter.updateDebugPreview(progress: progress, direction: direction)
    }

    public func updateDebugIntensity(_ intensity: Double) {
        guard isDebugging else { return }
        debugPresenter.setTuning(FoldTuning.default.withIntensity(intensity))
    }

    public func finishDebugSession() async {
        debugPresenter.endDebugPreview()
        guard isDebugging else { return }
        isDebugging = false
        guard !isTerminating else { return }
        applyRuntimePolicy()
        refreshMenu()
    }

    private var currentTuning: FoldTuning {
        FoldTuning.default.withIntensity(preferences.intensity)
    }

    private var runtimePermitted: Bool {
        productPermitted && !sessionRestricted
    }

    private var productPermitted: Bool {
        isStarted && preferences.isEnabled && permission.state == .granted
            && !isDebugging && !isTerminating
    }

    private func applyRuntimePolicy() {
        guard productPermitted else {
            stopAnimation()
            inputSource.stop()
            _ = lifecycle.setEnabled(false)
            sourceModeChanged(.unavailable)
            return
        }

        _ = lifecycle.setEnabled(true)
        lifecycle.setTuning(currentTuning)
        guard !sessionRestricted else {
            stopAnimation()
            inputSource.stop()
            sourceModeChanged(.unavailable)
            return
        }
        inputSource.setSessionRestricted(false)
        sourceModeChanged(inputSource.start())
    }

    private func receive(_ sample: AngleSample) {
        guard runtimePermitted else { return }
        let state = lifecycle.ingest(sample)
        updateAnimation(for: state)
    }

    private func sourceModeChanged(_ mode: InputSourceMode) {
        // Stopping for user preference, TCC, debug, or session authority does
        // not erase the last probed input capability. A genuine source loss
        // while permitted still reports unavailable until fallback binds.
        if mode == .unavailable, !runtimePermitted { return }
        guard !hasAppliedInputMode || inputMode != mode else {
            menuController?.updateInputMode(mode.menuTitle)
            return
        }
        hasAppliedInputMode = true
        inputMode = mode
        switch mode {
        case .sensor:
            _ = lifecycle.setInputAvailability(.sensor)
        case .timedFallback:
            _ = lifecycle.setInputAvailability(.timedFallback)
        case .unavailable:
            _ = lifecycle.setInputAvailability(.unavailable)
        }
        menuController?.updateInputMode(mode.menuTitle)
    }

    private func updateAnimation(for state: FoldState) {
        switch state.phase {
        case .folding, .unfolding:
            guard animation == nil else { return }
            animation = animationScheduler.schedule(interval: 1.0 / 60.0) { [weak self] in
                guard let self else { return }
                self.updateAnimation(for: self.lifecycle.tick(now: self.now()))
            }
        case .idle, .armed, .sealed:
            stopAnimation()
        }
    }

    private func stopAnimation() {
        animation?.cancel()
        animation = nil
    }

    private func finalizeSleep() {
        stopAnimation()
        sessionRestricted = true
        inputSource.stop()
        inputSource.setSessionRestricted(true)
        _ = lifecycle.systemWillSleep()
        sourceModeChanged(.unavailable)
        refreshMenu()
    }

    private func restrictSession(lockLifecycle: Bool) {
        stopAnimation()
        sessionRestricted = true
        inputSource.setSessionRestricted(true)
        inputSource.stop()
        if lockLifecycle { _ = lifecycle.sessionLocked() }
        sourceModeChanged(.unavailable)
    }

    private func unlockAndRestoreRuntime(explicitUnlock: Bool = false) async {
        guard isStarted, !isTerminating,
              explicitUnlock ? isExplicitUnlockAuthorizedNow() : sessionAccessNow() == .active
        else { return }
        guard !isUnlocking else { return }
        isUnlocking = true
        defer {
            isUnlocking = false
            if pendingExplicitUnlock {
                pendingExplicitUnlock = false
                // An intervening lock can invalidate the first capture. The
                // explicit unlock event retries only after that attempt ends.
                if sessionRestricted, isExplicitUnlockAuthorizedNow() {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        await self.screenDidUnlock(
                            sessionAccess: self.sessionAccessNow(),
                            onConsole: self.isCurrentConsoleNow()
                        )
                    }
                }
            }
        }
        inputSource.setSessionRestricted(true)
        sessionRestricted = false
        runOnboardingIfEligible(explicitUnlock: explicitUnlock)
        guard !sessionRestricted,
              (explicitUnlock ? isExplicitUnlockAuthorizedNow()
                : sessionAccessNow() == .active) else {
            restrictSession(lockLifecycle: true)
            refreshMenu()
            return
        }
        if preferences.isEnabled, permission.state == .granted, !isDebugging {
            _ = lifecycle.setEnabled(true)
            let state = await lifecycle.sessionUnlocked(
                firstFrameTimeout: 0.5,
                now: now
            )
            guard (explicitUnlock ? isExplicitUnlockAuthorizedNow()
                    : sessionAccessNow() == .active), !sessionRestricted,
                  !isTerminating else {
                restrictSession(lockLifecycle: true)
                refreshMenu()
                return
            }
            updateAnimation(for: state)
        }
        inputSource.setSessionRestricted(false)
        applyRuntimePolicy()
        refreshMenu()
    }

    private func retryHIDAfterWakeIfNeeded() {
        guard runtimePermitted, inputSource.isEnabled,
              inputSource.mode == .timedFallback else { return }
        inputSource.retryHID()
    }

    private func isExplicitUnlockAuthorizedNow() -> Bool {
        guard isCurrentConsoleNow() else { return false }
        return sessionAccessNow() != .restricted
    }

    private func runOnboardingIfEligible(explicitUnlock: Bool = false) {
        guard isStarted, !isTerminating, !sessionRestricted,
              (explicitUnlock ? isExplicitUnlockAuthorizedNow()
                : sessionAccessNow() == .active) else { return }
        _ = permission.runFirstLaunchOnboardingIfNeeded(
            enabled: preferences.isEnabled,
            presenter: onboarding
        )
    }

    private func abortDebugForRestriction() {
        debugSessionGeneration &+= 1
        debugScrubber.abortForSystemRestriction()
        debugPresenter.endDebugPreview()
        isDebugging = false
    }

    private func refreshMenu() {
        menuController?.update(makeSnapshot())
    }

    private func makeSnapshot() -> MenuBarSnapshot {
        MenuBarSnapshot(
            enabled: preferences.isEnabled,
            intensity: preferences.intensity,
            launchAtLogin: launchAtLogin.state,
            inputMode: inputMode.menuTitle,
            screenRecording: permission.state
        )
    }

    private func makeMenuActions() -> MenuBarActions {
        MenuBarActions(
            menuDidOpen: { [weak self] in self?.menuDidOpen() },
            setEnabled: { [weak self] in self?.setEnabled($0) },
            setIntensity: { [weak self] in self?.setIntensity($0) },
            setLaunchAtLogin: { [weak self] in self?.setLaunchAtLogin($0) },
            openLoginItemsSettings: { [weak self] in self?.openLaunchAtLoginSettings() },
            screenRecordingAction: { [weak self] in self?.screenRecordingAction() },
            openDebugScrubber: { [weak self] in self?.openDebugScrubber() },
            checkForUpdates: { [weak self] in
                self?.urlOpener.open(MenuBarController.releasesURL) ?? false
            },
            quit: { [weak self] in self?.terminateApplication() },
            reportError: { [weak self] in self?.reportError($0) }
        )
    }
}

public extension InputSourceMode {
    var menuTitle: String {
        switch self {
        case .sensor: "Lid angle sensor"
        case .timedFallback: "Timed fallback"
        case .unavailable: "Input unavailable"
        }
    }
}

@MainActor
private final class ProductionOverlayLifecycleOutput: FoldLifecycleOutput {
    let presenter: OverlayPresenter

    init(presenter: OverlayPresenter) { self.presenter = presenter }

    var captureExclusionWindowID: CGWindowID { presenter.windowID }
    func setSource(_ frame: CapturedFrame) throws { try presenter.setSource(frame) }
    func setFallbackSource() throws { try presenter.setFallbackSource() }
    func clearSource() { presenter.clearSource() }
    func update(_ state: FoldState) { presenter.update(state) }
    func hide() { presenter.hide() }
    func setReducedQuality(_ reduced: Bool) { presenter.setReducedQuality(reduced) }
    func setTuning(_ tuning: FoldTuning) { presenter.setTuning(tuning) }
    func reconfigureForBuiltInDisplay() -> Bool {
        presenter.reconfigureForBuiltInDisplay()
    }
}
