import AppKit
import LidRippleCore
import LidRippleOverlay
import LidRippleSensor

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let driver = FoldDriver()
    private var sensor: HIDAngleSource?
    private var overlay: OverlayPresenter?
    private var scriptedUnfoldTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Equivalent to LSUIElement for this unbundled package executable: no
        // Dock icon or normal application menu. Packaging arrives in M5.
        NSApp.setActivationPolicy(.accessory)

        overlay = OverlayPresenter()
        if overlay == nil {
            print("No built-in display on this Mac; the overlay is disabled.")
        }

        setUpStatusItem()
        observeSystemNotifications()
        startSensorIfAvailable()
    }

    func applicationWillTerminate(_ notification: Notification) {
        scriptedUnfoldTimer?.invalidate()
        sensor?.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
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

    private func startSensorIfAvailable() {
        let source = HIDAngleSource()
        guard source.isAvailable else {
            print(SensorProbe.probe().description)
            return
        }

        sensor = source
        do {
            try source.start { [weak self] sample in
                // HID samples arrive on the sensor's private queue. FoldDriver is
                // intentionally kept on the main actor with the AppKit presenter.
                // A serial dispatch queue preserves the sensor's sample ordering;
                // unstructured tasks would not provide that ordering guarantee.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let state = self.driver.ingest(sample)
                    self.overlay?.update(state)
                }
            }
        } catch {
            print("Failed to start the lid angle sensor: \(error)")
        }
    }

    private func observeSystemNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenDidUnlock),
            name: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }

    /// A sleep notification immediately seals the animation and cancels any
    /// scripted reveal already in flight.
    @objc private func willSleep() {
        scriptedUnfoldTimer?.invalidate()
        scriptedUnfoldTimer = nil
        overlay?.update(driver.signalSleep())
    }

    /// On unlock, reveal the freshly opened display over the driver's fixed
    /// scripted duration. Plan 2c will add a new screen capture at this call site.
    @objc private func screenDidUnlock() {
        scriptedUnfoldTimer?.invalidate()
        overlay?.update(
            driver.beginScriptedUnfold(now: ProcessInfo.processInfo.systemUptime)
        )

        let timer = Timer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(scriptedUnfoldTick),
            userInfo: nil,
            repeats: true
        )
        scriptedUnfoldTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func scriptedUnfoldTick(_ timer: Timer) {
        let state = driver.tick(now: ProcessInfo.processInfo.systemUptime)
        overlay?.update(state)
        if state.phase == .idle {
            timer.invalidate()
            scriptedUnfoldTimer = nil
        }
    }
}
