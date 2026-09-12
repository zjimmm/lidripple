import AppKit
import CoreGraphics
import LidRippleCapture
import LidRippleCore
import LidRippleIntegration
import LidRippleOverlay
import LidRippleSensor

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var sensor: HIDAngleSource?
    private var output: OverlayLifecycleOutput?
    private var lifecycle: FoldLifecycleCoordinator?
    private var animationTimer: Timer?
    private var sensorRecoveryTask: Task<Void, Never>?
    private let sensorRecovery = SensorRecovery()
    private var sensorGeneration: UInt64 = 0
    private var terminationCleanupStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Equivalent to LSUIElement for this unbundled package executable: no
        // Dock icon or normal application menu. Bundle metadata arrives in M5.
        NSApp.setActivationPolicy(.accessory)

        configurePipeline()
        setUpStatusItem()
        observeSystemNotifications()
        updateQualityMode()

        if currentSessionAccess() == .restricted {
            lifecycle?.sessionLocked()
        } else {
            _ = startSensorIfAvailable()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationCleanupStarted else { return .terminateNow }
        terminationCleanupStarted = true
        animationTimer?.invalidate()
        sensorRecoveryTask?.cancel()
        stopSensor()

        guard let lifecycle else { return .terminateNow }
        Task { @MainActor in
            await lifecycle.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        animationTimer?.invalidate()
        sensorRecoveryTask?.cancel()
        stopSensor()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    private func configurePipeline() {
        guard let presenter = OverlayPresenter() else {
            print("No built-in display or Metal renderer is available; lidripple is disabled.")
            return
        }

        do {
            let capture = try CaptureCoordinator()
            let output = OverlayLifecycleOutput(presenter: presenter)
            self.output = output
            lifecycle = FoldLifecycleCoordinator(
                capture: capture,
                output: output,
                displayID: { BuiltInDisplay.displayID() }
            )
        } catch {
            print("Screen capture is unavailable: \(error)")
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "◐"

        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: "Quit lidripple",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @discardableResult
    private func startSensorIfAvailable(reportUnavailable: Bool = true) -> Bool {
        stopSensor()

        let generation = sensorGeneration
        let source = HIDAngleSource { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.sensorGeneration == generation else { return }
                self.lifecycle?.sensorUnavailable()
                self.recoverSensorAfterWake()
            }
        }
        guard source.isAvailable else {
            if reportUnavailable {
                lifecycle?.sensorUnavailable()
                print(SensorProbe.probe().description)
            }
            return false
        }

        do {
            try source.start { [weak self] sample in
                // HID callbacks arrive on a private serial queue; dispatching to
                // the main actor preserves their order for the pure driver.
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.sensorGeneration == generation,
                          let lifecycle = self.lifecycle
                    else { return }
                    let state = lifecycle.ingest(sample)
                    self.updateAnimationTimer(for: state)
                }
            }
            sensor = source
            lifecycle?.sensorRecovered()
            return true
        } catch {
            if reportUnavailable {
                lifecycle?.sensorUnavailable()
                print("Failed to start the lid angle sensor: \(error)")
            }
            return false
        }
    }

    private func recoverSensorAfterWake() {
        sensorRecoveryTask?.cancel()
        stopSensor()

        sensorRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let outcome = try await self.sensorRecovery.run {
                    self.startSensorIfAvailable(reportUnavailable: false)
                }
                if case .fallbackRequired = outcome {
                    // M5 observes this state and binds EventAngleSource. M3
                    // guarantees the failed HID cycle leaves no capture or
                    // visible overlay behind.
                    self.lifecycle?.sensorUnavailable()
                }
            } catch is CancellationError {
                return
            } catch {
                print("Sensor recovery failed: \(error)")
            }
            self.sensorRecoveryTask = nil
        }
    }

    private func observeSystemNotifications() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self,
            selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(sessionResignedActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(sessionBecameActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            self,
            selector: #selector(screenDidLock),
            name: Notification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        distributed.addObserver(
            self,
            selector: #selector(screenDidUnlock),
            name: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(qualityEnvironmentChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(qualityEnvironmentChanged),
            name: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }

    @objc private func willSleep() {
        stopAnimationTimer()
        sensorRecoveryTask?.cancel()
        stopSensor()
        lifecycle?.systemWillSleep()
    }

    @objc private func didWake() {
        recoverSensorAfterWake()
        // Only a positively unlocked session may reveal here. If the private
        // screen-lock dictionary key is absent, wait for the explicit
        // com.apple.screenIsUnlocked notification instead of risking drawing
        // above loginwindow.
        if currentSessionAccess() == .active { beginUnlockReveal() }
    }

    @objc private func screenDidLock() {
        stopAnimationTimer()
        sensorRecoveryTask?.cancel()
        stopSensor()
        lifecycle?.sessionLocked()
    }

    @objc private func screenDidUnlock() {
        beginUnlockReveal()
        recoverSensorAfterWake()
    }

    private func beginUnlockReveal() {
        stopAnimationTimer()
        Task { @MainActor [weak self] in
            guard let self, let lifecycle = self.lifecycle else { return }
            let state = await lifecycle.sessionUnlocked()
            self.updateAnimationTimer(for: state)
        }
    }

    @objc private func sessionResignedActive() {
        stopAnimationTimer()
        sensorRecoveryTask?.cancel()
        stopSensor()
        lifecycle?.sessionResignedActive()
    }

    @objc private func sessionBecameActive() {
        lifecycle?.sessionBecameActive()
        recoverSensorAfterWake()
    }

    @objc private func displayConfigurationChanged() {
        stopAnimationTimer()
        let state = lifecycle?.displayConfigurationChanged()
        updateAnimationTimer(for: state)
    }

    @objc private func qualityEnvironmentChanged() {
        updateQualityMode()
    }

    private func updateQualityMode() {
        let info = ProcessInfo.processInfo
        let thermalPressure = info.thermalState == .serious || info.thermalState == .critical
        lifecycle?.setReducedQuality(thermalPressure || info.isLowPowerModeEnabled)
    }

    private func updateAnimationTimer(for state: FoldState?) {
        guard let state else { return }
        switch state.phase {
        case .folding, .unfolding:
            startAnimationTimerIfNeeded()
        case .idle, .armed, .sealed:
            stopAnimationTimer()
        }
    }

    private func startAnimationTimerIfNeeded() {
        guard animationTimer == nil else { return }
        let timer = Timer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(animationTick),
            userInfo: nil,
            repeats: true
        )
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    @objc private func animationTick(_ timer: Timer) {
        guard let lifecycle else {
            stopAnimationTimer()
            return
        }
        let state = lifecycle.tick(now: ProcessInfo.processInfo.systemUptime)
        updateAnimationTimer(for: state)
    }

    private func currentSessionAccess() -> ConsoleSessionAccess {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return .unknown
        }
        // The first key is a CGSession.h CFSTR macro (not imported by Swift).
        // The second is emitted by WindowServer but not declared in the public
        // SDK; treating its absence as unknown is the fail-closed wake policy.
        return .resolve(
            onConsole: dictionary["kCGSSessionOnConsoleKey"] as? Bool,
            screenLocked: dictionary["CGSSessionScreenIsLocked"] as? Bool
        )
    }

    private func stopSensor() {
        sensorGeneration &+= 1
        sensor?.stop()
        sensor = nil
    }
}
