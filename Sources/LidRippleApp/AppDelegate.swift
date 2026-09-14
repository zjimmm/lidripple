import AppKit
import CoreGraphics
import LidRippleAppSupport
import LidRippleIntegration
import OSLog

/// Thin AppKit bridge. Product policy and ownership live in AppCoordinator so
/// notification ordering can be tested without a real TCC prompt or desktop.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let wakeLog = Logger(subsystem: "com.lidripple.app", category: "wake")
    private var coordinator: AppCoordinator?
    private var unavailableStatusItem: NSStatusItem?
    private var isObservingSystemNotifications = false
    private var terminationCleanupStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Info.plist supplies LSUIElement in the installed bundle; this keeps
        // direct SwiftPM launches agent-only as defense in depth.
        NSApp.setActivationPolicy(.accessory)

        // Observe display changes even when the built-in screen is temporarily
        // unavailable (for example, when launched in closed clamshell mode).
        // In that state the menu must remain usable and construction can be
        // retried when the display returns.
        observeSystemNotifications()
        attemptStartup()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        coordinator?.applicationDidBecomeActive()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationCleanupStarted else { return .terminateNow }
        terminationCleanupStarted = true
        guard let coordinator else { return .terminateNow }

        Task { @MainActor in
            await coordinator.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        removeUnavailableStatusItem()
    }

    private func attemptStartup() {
        guard coordinator == nil, !terminationCleanupStarted else { return }
        do {
            let coordinator = try AppCoordinator.production(
                terminateApplication: { NSApp.terminate(nil) },
                reportError: { [weak self] message in self?.presentError(message) }
            )
            self.coordinator = coordinator
            removeUnavailableStatusItem()
            updateQualityMode()
            coordinator.start(sessionAccess: currentSessionAccess())
        } catch {
            // Do not repeatedly display modal alerts as displays reconnect.
            // An accessory app with no product menu would otherwise be stranded.
            installUnavailableStatusItem(reason: error)
        }
    }

    private func installUnavailableStatusItem(reason: Error) {
        let item: NSStatusItem
        if let unavailableStatusItem {
            item = unavailableStatusItem
        } else {
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = StatusBarIcon.make()
            item.button?.setAccessibilityLabel("LidRipple unavailable")
            unavailableStatusItem = item
        }
        let reasonText: String
        switch reason as? AppCoordinatorConstructionError {
        case .noBuiltInDisplayOrMetalRenderer:
            reasonText = "Built-in display or Metal renderer unavailable"
        case .captureUnavailable:
            reasonText = "Screen capture is unavailable"
        case nil:
            reasonText = "Unable to start: \(reason.localizedDescription)"
        }
        item.button?.toolTip = "LidRipple: \(reasonText)"

        let menu = NSMenu()
        let status = NSMenuItem(title: "LidRipple unavailable", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        let detail = NSMenuItem(title: reasonText, action: nil, keyEquivalent: "")
        detail.isEnabled = false
        menu.addItem(detail)
        menu.addItem(.separator())
        let retry = NSMenuItem(title: "Retry", action: #selector(retryStartup), keyEquivalent: "r")
        retry.target = self
        menu.addItem(retry)
        let quit = NSMenuItem(title: "Quit LidRipple", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
    }

    private func removeUnavailableStatusItem() {
        guard let unavailableStatusItem else { return }
        NSStatusBar.system.removeStatusItem(unavailableStatusItem)
        self.unavailableStatusItem = nil
    }

    @objc private func retryStartup() { attemptStartup() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func observeSystemNotifications() {
        guard !isObservingSystemNotifications else { return }
        isObservingSystemNotifications = true
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
        wakeLog.notice("willSleep")
        coordinator?.systemWillSleep()
    }

    @objc private func didWake() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let access = self.currentSessionAccess()
            self.wakeLog.notice("didWake access=\(String(describing: access), privacy: .public)")
            await self.coordinator?.systemDidWake(sessionAccess: access)
        }
    }

    @objc private func screenDidLock() {
        wakeLog.notice("screenDidLock")
        coordinator?.screenDidLock()
    }

    @objc private func screenDidUnlock() {
        guard let eventCoordinator = coordinator else { return }
        let generation = eventCoordinator.sessionEventGeneration
        Task { @MainActor [weak self, weak eventCoordinator] in
            guard let self, let eventCoordinator,
                  generation == eventCoordinator.sessionEventGeneration else { return }
            // Allow the lock-state dictionary to catch up with the public
            // notification, while the generation binds it to this event.
            let session = self.currentSessionSnapshot()
            self.wakeLog.notice(
                "screenDidUnlock access=\(String(describing: session.access), privacy: .public) onConsole=\(session.onConsole)"
            )
            await eventCoordinator.screenDidUnlock(
                sessionAccess: session.access,
                onConsole: session.onConsole,
                notificationGeneration: generation
            )
        }
    }

    @objc private func sessionResignedActive() {
        wakeLog.notice("sessionResignedActive")
        coordinator?.sessionResignedActive()
    }
    @objc private func sessionBecameActive() {
        let access = currentSessionAccess()
        wakeLog.notice("sessionBecameActive access=\(String(describing: access), privacy: .public)")
        coordinator?.sessionBecameActive(sessionAccess: access)
    }
    @objc private func displayConfigurationChanged() {
        if let coordinator {
            coordinator.displayConfigurationChanged()
        } else {
            attemptStartup()
        }
    }
    @objc private func qualityEnvironmentChanged() { updateQualityMode() }

    private func updateQualityMode() {
        let info = ProcessInfo.processInfo
        let thermalPressure = info.thermalState == .serious || info.thermalState == .critical
        coordinator?.setReducedQuality(thermalPressure || info.isLowPowerModeEnabled)
    }

    private func currentSessionAccess() -> ConsoleSessionAccess {
        currentSessionSnapshot().access
    }

    /// Read both predicates from one dictionary so a fast lock/switch cannot
    /// produce an internally inconsistent unlock-notification snapshot.
    private func currentSessionSnapshot() -> (access: ConsoleSessionAccess, onConsole: Bool) {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return (.unknown, false)
        }
        let onConsole = dictionary["kCGSSessionOnConsoleKey"] as? Bool
        return (
            .resolve(
                onConsole: onConsole,
                screenLocked: dictionary["CGSSessionScreenIsLocked"] as? Bool
            ),
            onConsole == true
        )
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "LidRipple"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
