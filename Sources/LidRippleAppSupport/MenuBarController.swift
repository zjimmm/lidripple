import AppKit
import Foundation

public struct MenuBarSnapshot: Equatable, Sendable {
    public var enabled: Bool
    public var intensity: Double
    public var launchAtLogin: LaunchAtLoginServiceStatus
    public var inputMode: String
    public var screenRecording: ScreenRecordingPermissionState

    public init(
        enabled: Bool,
        intensity: Double,
        launchAtLogin: LaunchAtLoginServiceStatus,
        inputMode: String,
        screenRecording: ScreenRecordingPermissionState
    ) {
        self.enabled = enabled
        self.intensity = AppPreferences.clampIntensity(intensity)
        self.launchAtLogin = launchAtLogin
        self.inputMode = inputMode
        self.screenRecording = screenRecording
    }
}

@MainActor
public struct MenuBarActions {
    /// A direct status-menu interaction is evidence the user's desktop UI is
    /// reachable when macOS omits its private lock-state dictionary key.
    public var menuDidOpen: () -> Void
    public var setEnabled: (Bool) -> Void
    public var setIntensity: (Double) -> Void
    public var setLaunchAtLogin: (Bool) -> Void
    public var openLoginItemsSettings: () -> Void
    public var screenRecordingAction: () -> Void
    public var openDebugScrubber: () -> Void
    /// Returns false when the default browser could not be opened.
    public var checkForUpdates: () -> Bool
    public var quit: () -> Void
    public var reportError: (String) -> Void

    public init(
        menuDidOpen: @escaping () -> Void = {},
        setEnabled: @escaping (Bool) -> Void,
        setIntensity: @escaping (Double) -> Void,
        setLaunchAtLogin: @escaping (Bool) -> Void,
        openLoginItemsSettings: @escaping () -> Void,
        screenRecordingAction: @escaping () -> Void,
        openDebugScrubber: @escaping () -> Void,
        checkForUpdates: @escaping () -> Bool,
        quit: @escaping () -> Void,
        reportError: @escaping (String) -> Void
    ) {
        self.menuDidOpen = menuDidOpen
        self.setEnabled = setEnabled
        self.setIntensity = setIntensity
        self.setLaunchAtLogin = setLaunchAtLogin
        self.openLoginItemsSettings = openLoginItemsSettings
        self.screenRecordingAction = screenRecordingAction
        self.openDebugScrubber = openDebugScrubber
        self.checkForUpdates = checkForUpdates
        self.quit = quit
        self.reportError = reportError
    }
}

@MainActor
public final class MenuBarController: NSObject {
    public static let releasesURL = URL(
        string: "https://github.com/zjimmm/lidripple/releases"
    )!

    public enum ItemID: String {
        case enabled
        case intensity
        case launchAtLogin
        case inputMode
        case screenRecording
        case debugScrubber
        case checkForUpdates
        case quit
    }

    public let menu = NSMenu()
    public private(set) var snapshot: MenuBarSnapshot

    private let actions: MenuBarActions
    private var statusItem: NSStatusItem?
    private let enabledItem = NSMenuItem()
    private let intensityItem = NSMenuItem()
    private let launchItem = NSMenuItem()
    private let inputModeItem = NSMenuItem()
    private let screenRecordingItem = NSMenuItem()
    private let debugItem = NSMenuItem()
    private let updateItem = NSMenuItem()
    private let quitItem = NSMenuItem()
    private var intensitySlider: NSSlider?
    private var intensityLabel: NSTextField?

    public init(
        snapshot: MenuBarSnapshot,
        actions: MenuBarActions,
        installStatusItem: Bool = true
    ) {
        self.snapshot = snapshot
        self.actions = actions
        super.init()
        menu.delegate = self
        buildMenu()
        update(snapshot)

        if installStatusItem {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.title = "◐"
            item.button?.setAccessibilityLabel("lidripple")
            item.menu = menu
            statusItem = item
        }
    }

    public func uninstall() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    public func update(_ snapshot: MenuBarSnapshot) {
        self.snapshot = snapshot
        enabledItem.state = snapshot.enabled ? .on : .off

        let intensity = AppPreferences.clampIntensity(snapshot.intensity)
        intensitySlider?.doubleValue = intensity
        intensityLabel?.stringValue = "Intensity: \(Int((intensity * 100).rounded()))%"

        switch snapshot.launchAtLogin {
        case .enabled:
            launchItem.title = "Launch at Login"
            launchItem.state = .on
            launchItem.isEnabled = true
        case .disabled:
            launchItem.title = "Launch at Login"
            launchItem.state = .off
            launchItem.isEnabled = true
        case .requiresUserApproval:
            launchItem.title = "Launch at Login — Needs Approval…"
            launchItem.state = .on
            launchItem.isEnabled = true
        case .unavailable:
            launchItem.title = "Launch at Login — Unavailable"
            launchItem.state = .off
            launchItem.isEnabled = false
        }

        inputModeItem.title = "Input Mode: \(snapshot.inputMode)"
        inputModeItem.toolTip = snapshot.inputMode == "Timed fallback"
            ? "Sleep-event timing only: no angle tracking or reversal. A no-sleep clamshell close may not be detected."
            : nil
        switch snapshot.screenRecording {
        case .granted:
            screenRecordingItem.title = "Screen Recording: Granted"
            screenRecordingItem.isEnabled = false
        case .notDetermined:
            screenRecordingItem.title = "Screen Recording: Set Up…"
            screenRecordingItem.isEnabled = true
        case .denied:
            screenRecordingItem.title = "Screen Recording: Needs Permission…"
            screenRecordingItem.isEnabled = true
        }
    }

    public func updateEnabled(_ enabled: Bool) {
        var next = snapshot
        next.enabled = enabled
        update(next)
    }

    public func updateIntensity(_ intensity: Double) {
        var next = snapshot
        next.intensity = AppPreferences.clampIntensity(intensity)
        update(next)
    }

    public func updateLaunchAtLogin(_ state: LaunchAtLoginServiceStatus) {
        var next = snapshot
        next.launchAtLogin = state
        update(next)
    }

    public func updateInputMode(_ inputMode: String) {
        var next = snapshot
        next.inputMode = inputMode
        update(next)
    }

    public func updateScreenRecording(_ state: ScreenRecordingPermissionState) {
        var next = snapshot
        next.screenRecording = state
        update(next)
    }

    private func buildMenu() {
        configure(
            enabledItem,
            id: .enabled,
            title: "Enable lidripple",
            action: #selector(toggleEnabled)
        )
        menu.addItem(enabledItem)

        let intensityView = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 54))
        let label = NSTextField(labelWithString: "Intensity: 100%")
        label.frame = NSRect(x: 14, y: 29, width: 232, height: 17)
        let slider = NSSlider(
            value: 1,
            minValue: 0.5,
            maxValue: 1,
            target: self,
            action: #selector(intensityChanged)
        )
        slider.frame = NSRect(x: 12, y: 3, width: 236, height: 24)
        slider.isContinuous = true
        slider.setAccessibilityLabel("Fold effect intensity")
        intensityView.addSubview(label)
        intensityView.addSubview(slider)
        intensityItem.identifier = identifier(.intensity)
        intensityItem.view = intensityView
        menu.addItem(intensityItem)
        intensityLabel = label
        intensitySlider = slider

        configure(
            launchItem,
            id: .launchAtLogin,
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin)
        )
        menu.addItem(launchItem)

        configure(inputModeItem, id: .inputMode, title: "Input Mode", action: nil)
        inputModeItem.isEnabled = false
        menu.addItem(inputModeItem)

        configure(
            screenRecordingItem,
            id: .screenRecording,
            title: "Screen Recording",
            action: #selector(screenRecordingSelected)
        )
        menu.addItem(screenRecordingItem)

        menu.addItem(.separator())
        configure(
            debugItem,
            id: .debugScrubber,
            title: "Open Debug Scrubber…",
            action: #selector(openDebugScrubber),
            keyEquivalent: "d"
        )
        menu.addItem(debugItem)

        configure(
            updateItem,
            id: .checkForUpdates,
            title: "Check for Updates…",
            action: #selector(checkForUpdates)
        )
        menu.addItem(updateItem)

        menu.addItem(.separator())
        configure(
            quitItem,
            id: .quit,
            title: "Quit lidripple",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
    }

    private func configure(
        _ item: NSMenuItem,
        id: ItemID,
        title: String,
        action: Selector?,
        keyEquivalent: String = ""
    ) {
        item.identifier = identifier(id)
        item.title = title
        item.target = self
        item.action = action
        item.keyEquivalent = keyEquivalent
    }

    private func identifier(_ id: ItemID) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("lidripple.menu.\(id.rawValue)")
    }

    @objc private func toggleEnabled() {
        actions.setEnabled(!snapshot.enabled)
    }

    @objc private func intensityChanged(_ sender: NSSlider) {
        let value = AppPreferences.clampIntensity(sender.doubleValue)
        intensityLabel?.stringValue = "Intensity: \(Int((value * 100).rounded()))%"
        actions.setIntensity(value)
    }

    @objc private func toggleLaunchAtLogin() {
        if snapshot.launchAtLogin == .requiresUserApproval {
            actions.openLoginItemsSettings()
        } else {
            actions.setLaunchAtLogin(snapshot.launchAtLogin != .enabled)
        }
    }

    @objc private func screenRecordingSelected() { actions.screenRecordingAction() }
    @objc private func openDebugScrubber() { actions.openDebugScrubber() }

    @objc private func checkForUpdates() {
        guard actions.checkForUpdates() else {
            actions.reportError("Unable to open the lidripple Releases page in your browser.")
            return
        }
    }

    @objc private func quit() { actions.quit() }
}

extension MenuBarController: NSMenuDelegate {
    public func menuWillOpen(_ menu: NSMenu) {
        actions.menuDidOpen()
    }
}
