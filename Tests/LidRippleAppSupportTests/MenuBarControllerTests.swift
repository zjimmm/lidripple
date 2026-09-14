import AppKit
import Testing
import LidRippleCore
@testable import LidRippleAppSupport

@Suite(.serialized)
@MainActor
struct MenuBarControllerTests {
    @Test func statusIconUsesNativeTemplateTintAndCompactSize() {
        let icon = StatusBarIcon.make()
        #expect(icon.isTemplate)
        #expect(icon.size == NSSize(width: 18, height: 18))
        #expect(icon.accessibilityDescription == "LidRipple")
        #expect(icon.tiffRepresentation != nil)
    }
    @Test func effectMenuForwardsSelectionAndReflectsSnapshot() throws {
        let recorder = ActionRecorder()
        let controller = makeController(recorder: recorder)
        let submenu = try #require(item(.effect, in: controller).submenu)
        #expect(submenu.items.map(\.title) == ["Fold", "Ripple"])
        #expect(submenu.items[0].state == .on)
        submenu.performActionForItem(at: 1)
        #expect(recorder.effects == [.ripple])
        var snapshot = controller.snapshot
        snapshot.effect = .ripple
        controller.update(snapshot)
        #expect(item(.effect, in: controller).title == "Effect: Ripple")
        #expect(submenu.items[0].state == .off)
        #expect(submenu.items[1].state == .on)
    }
    @Test func menuHasCompleteProductSurfaceInRequiredOrder() {
        let controller = makeController(recorder: ActionRecorder())
        let ids = controller.menu.items.compactMap(\.identifier?.rawValue)
        #expect(ids == [
            "lidripple.menu.enabled",
            "lidripple.menu.effect",
            "lidripple.menu.launchAtLogin",
            "lidripple.menu.inputMode",
            "lidripple.menu.screenRecording",
            "lidripple.menu.debugScrubber",
            "lidripple.menu.checkForUpdates",
            "lidripple.menu.quit",
        ])
        #expect(item(.debugScrubber, in: controller).keyEquivalent == "d")
        #expect(item(.enabled, in: controller).title == "Enable LidRipple")
        #expect(item(.quit, in: controller).title == "Quit LidRipple")
    }

    @Test func refreshCoversDisabledFallbackPermissionAndApprovalStates() {
        let controller = makeController(recorder: ActionRecorder())
        controller.update(MenuBarSnapshot(
            enabled: false,
            intensity: 0.5,
            launchAtLogin: .requiresUserApproval,
            inputMode: "Sensor-less (experimental)",
            screenRecording: .denied
        ))

        #expect(item(.enabled, in: controller).state == .off)
        #expect(item(.launchAtLogin, in: controller).state == .on)
        #expect(item(.launchAtLogin, in: controller).title.contains("Needs Approval"))
        #expect(item(.inputMode, in: controller).title == "Input Mode: Sensor-less (experimental)")
        let help = item(.inputMode, in: controller).toolTip
        #expect(help?.contains("Unverified on a Mac without a lid-angle sensor") == true)
        #expect(help?.contains("A visible close animation is currently unavailable") == true)
        #expect(help?.contains("Physical angle tracking and mid-close reversal are unavailable") == true)
        #expect(help?.contains("no-sleep clamshell close may be undetectable") == true)
        #expect(help?.contains("fresh opening after unlock requires an active session, built-in display, and Screen Recording permission") == true)
        #expect(!item(.inputMode, in: controller).isEnabled)
        #expect(item(.screenRecording, in: controller).title.contains("Needs Permission"))
        #expect(item(.screenRecording, in: controller).isEnabled)

        #expect(controller.menu.items.allSatisfy { $0.view == nil })
    }

    @Test func refreshCoversSensorUnavailableAndGrantedStates() {
        let controller = makeController(recorder: ActionRecorder())
        controller.update(MenuBarSnapshot(
            enabled: true,
            intensity: 0.75,
            launchAtLogin: .unavailable("not bundled"),
            inputMode: "Input unavailable",
            screenRecording: .granted
        ))
        #expect(item(.enabled, in: controller).state == .on)
        #expect(item(.launchAtLogin, in: controller).title.contains("Unavailable"))
        #expect(!item(.launchAtLogin, in: controller).isEnabled)
        #expect(item(.inputMode, in: controller).title == "Input Mode: Input unavailable")
        #expect(item(.inputMode, in: controller).toolTip == nil)
        #expect(item(.screenRecording, in: controller).title == "Screen Recording: Granted")
        #expect(!item(.screenRecording, in: controller).isEnabled)

        controller.update(MenuBarSnapshot(
            enabled: true,
            intensity: 0.75,
            launchAtLogin: .enabled,
            inputMode: "Lid angle sensor",
            screenRecording: .granted
        ))
        #expect(item(.inputMode, in: controller).title == "Input Mode: Lid angle sensor")
        #expect(item(.inputMode, in: controller).toolTip == nil)
    }

    @Test func actionsForwardValuesWithoutPerformingPlatformWork() {
        let recorder = ActionRecorder()
        let controller = makeController(recorder: recorder)

        perform(.enabled, in: controller)
        #expect(recorder.enabledValues == [false])

        perform(.launchAtLogin, in: controller)
        #expect(recorder.loginValues == [true])
        perform(.screenRecording, in: controller)
        perform(.debugScrubber, in: controller)
        perform(.checkForUpdates, in: controller)
        perform(.quit, in: controller)
        #expect(recorder.screenRecordingCount == 1)
        #expect(recorder.debugCount == 1)
        #expect(recorder.updateCount == 1)
        #expect(recorder.quitCount == 1)
        #expect(recorder.errors.isEmpty)
    }

    @Test func approvalRowOpensSettingsAndBrowserFailureIsVisible() {
        let recorder = ActionRecorder()
        recorder.updateResult = false
        let controller = makeController(recorder: recorder)
        controller.update(MenuBarSnapshot(
            enabled: true,
            intensity: 1,
            launchAtLogin: .requiresUserApproval,
            inputMode: "Lid angle sensor",
            screenRecording: .notDetermined
        ))
        perform(.launchAtLogin, in: controller)
        perform(.checkForUpdates, in: controller)
        #expect(recorder.loginSettingsCount == 1)
        #expect(recorder.loginValues.isEmpty)
        #expect(recorder.errors.count == 1)
        #expect(MenuBarController.releasesURL.scheme == "https")
        #expect(MenuBarController.releasesURL.host == "github.com")
    }

    @Test func appKitStatusItemSmokeDoesNotInvokeAnyAction() {
        let recorder = ActionRecorder()
        let controller = makeController(recorder: recorder, installStatusItem: true)
        #expect(controller.menu.numberOfItems == 10)
        #expect(recorder.totalActionCount == 0)
        controller.uninstall()
    }

    @Test func menuOpenReportsDirectUserInteraction() {
        let recorder = ActionRecorder()
        let controller = makeController(recorder: recorder)
        controller.menuWillOpen(controller.menu)
        #expect(recorder.menuOpenCount == 1)
    }

    private func makeController(
        recorder: ActionRecorder,
        installStatusItem: Bool = false
    ) -> MenuBarController {
        MenuBarController(
            snapshot: MenuBarSnapshot(
                enabled: true,
                intensity: 1,
                launchAtLogin: .disabled,
                inputMode: "Lid angle sensor",
                screenRecording: .notDetermined
            ),
            actions: MenuBarActions(
                menuDidOpen: { recorder.menuOpenCount += 1 },
                setEffect: { recorder.effects.append($0) },
                setEnabled: { recorder.enabledValues.append($0) },
                setIntensity: { recorder.intensities.append($0) },
                setLaunchAtLogin: { recorder.loginValues.append($0) },
                openLoginItemsSettings: { recorder.loginSettingsCount += 1 },
                screenRecordingAction: { recorder.screenRecordingCount += 1 },
                openDebugScrubber: { recorder.debugCount += 1 },
                checkForUpdates: {
                    recorder.updateCount += 1
                    return recorder.updateResult
                },
                quit: { recorder.quitCount += 1 },
                reportError: { recorder.errors.append($0) }
            ),
            installStatusItem: installStatusItem
        )
    }

    private func item(
        _ id: MenuBarController.ItemID,
        in controller: MenuBarController
    ) -> NSMenuItem {
        controller.menu.items.first {
            $0.identifier?.rawValue == "lidripple.menu.\(id.rawValue)"
        }!
    }

    private func perform(_ id: MenuBarController.ItemID, in controller: MenuBarController) {
        let target = item(id, in: controller)
        let index = controller.menu.index(of: target)
        controller.menu.performActionForItem(at: index)
    }

}

@MainActor
private final class ActionRecorder {
    var effects: [DesktopEffect] = []
    var menuOpenCount = 0
    var enabledValues: [Bool] = []
    var intensities: [Double] = []
    var loginValues: [Bool] = []
    var loginSettingsCount = 0
    var screenRecordingCount = 0
    var debugCount = 0
    var updateCount = 0
    var updateResult = true
    var quitCount = 0
    var errors: [String] = []

    var totalActionCount: Int {
        enabledValues.count + intensities.count + loginValues.count + loginSettingsCount
            + screenRecordingCount + debugCount + updateCount + quitCount + errors.count
    }
}
