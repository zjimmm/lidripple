import AppKit
import Testing
@testable import LidRippleAppSupport

@Suite(.serialized)
@MainActor
struct MenuBarControllerTests {
    @Test func menuHasCompleteProductSurfaceInRequiredOrder() {
        let controller = makeController(recorder: ActionRecorder())
        let ids = controller.menu.items.compactMap(\.identifier?.rawValue)
        #expect(ids == [
            "lidripple.menu.enabled",
            "lidripple.menu.intensity",
            "lidripple.menu.launchAtLogin",
            "lidripple.menu.inputMode",
            "lidripple.menu.screenRecording",
            "lidripple.menu.debugScrubber",
            "lidripple.menu.checkForUpdates",
            "lidripple.menu.quit",
        ])
        #expect(item(.debugScrubber, in: controller).keyEquivalent == "d")
    }

    @Test func refreshCoversDisabledFallbackPermissionAndApprovalStates() {
        let controller = makeController(recorder: ActionRecorder())
        controller.update(MenuBarSnapshot(
            enabled: false,
            intensity: 0.5,
            launchAtLogin: .requiresUserApproval,
            inputMode: "Timed fallback",
            screenRecording: .denied
        ))

        #expect(item(.enabled, in: controller).state == .off)
        #expect(item(.launchAtLogin, in: controller).state == .on)
        #expect(item(.launchAtLogin, in: controller).title.contains("Needs Approval"))
        #expect(item(.inputMode, in: controller).title == "Input Mode: Timed fallback")
        #expect(item(.inputMode, in: controller).toolTip?.contains("no angle tracking") == true)
        #expect(!item(.inputMode, in: controller).isEnabled)
        #expect(item(.screenRecording, in: controller).title.contains("Needs Permission"))
        #expect(item(.screenRecording, in: controller).isEnabled)

        let slider = intensitySlider(in: controller)
        #expect(slider?.doubleValue == 0.5)
        let label = intensityLabel(in: controller)
        #expect(label?.stringValue == "Intensity: 50%")
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
        #expect(item(.screenRecording, in: controller).title == "Screen Recording: Granted")
        #expect(!item(.screenRecording, in: controller).isEnabled)
    }

    @Test func actionsForwardValuesWithoutPerformingPlatformWork() {
        let recorder = ActionRecorder()
        let controller = makeController(recorder: recorder)

        perform(.enabled, in: controller)
        #expect(recorder.enabledValues == [false])

        let slider = intensitySlider(in: controller)!
        slider.doubleValue = 0.63
        slider.sendAction(slider.action, to: slider.target)
        #expect(recorder.intensities == [0.63])

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

    private func intensitySlider(in controller: MenuBarController) -> NSSlider? {
        item(.intensity, in: controller).view?.subviews.compactMap { $0 as? NSSlider }.first
    }

    private func intensityLabel(in controller: MenuBarController) -> NSTextField? {
        item(.intensity, in: controller).view?.subviews.compactMap { $0 as? NSTextField }.first
    }
}

@MainActor
private final class ActionRecorder {
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
