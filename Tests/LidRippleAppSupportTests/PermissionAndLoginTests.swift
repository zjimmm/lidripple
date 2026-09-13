import Foundation
import Testing
@testable import LidRippleAppSupport

@Suite(.serialized)
@MainActor
struct PermissionAndLoginTests {
    @Test func permissionStateUsesPreflightAndPersistedRequestFact() {
        #expect(ScreenRecordingPermissionController.resolve(
            preflightGranted: true,
            requestMade: false
        ) == .granted)
        #expect(ScreenRecordingPermissionController.resolve(
            preflightGranted: false,
            requestMade: false
        ) == .notDetermined)
        #expect(ScreenRecordingPermissionController.resolve(
            preflightGranted: false,
            requestMade: true
        ) == .denied)
    }

    @Test func notNowNeverRequestsAndDoesNotRepeatOnboarding() {
        let store = MemoryPreferences()
        let preferences = AppPreferences(storage: store)
        let service = FakePermissionService()
        let opener = FakeURLOpener()
        let controller = ScreenRecordingPermissionController(
            service: service,
            preferences: preferences,
            urlOpener: opener
        )
        let presenter = FakeOnboardingPresenter(choice: .notNow)

        #expect(controller.runFirstLaunchOnboardingIfNeeded(
            enabled: true,
            presenter: presenter
        ) == .notDetermined)
        _ = controller.runFirstLaunchOnboardingIfNeeded(enabled: true, presenter: presenter)
        #expect(presenter.presentCount == 1)
        #expect(service.requestCount == 0)
        #expect(preferences.screenRecordingOnboardingCompleted)
        #expect(!preferences.screenRecordingRequestMade)
    }

    @Test func explanationAlwaysPrecedesRequest() {
        let events = EventLog()
        let preferences = AppPreferences(storage: MemoryPreferences())
        let service = FakePermissionService(requestResult: false, events: events)
        let presenter = FakeOnboardingPresenter(choice: .continue, events: events)
        let controller = ScreenRecordingPermissionController(
            service: service,
            preferences: preferences,
            urlOpener: FakeURLOpener()
        )

        #expect(controller.runFirstLaunchOnboardingIfNeeded(
            enabled: true,
            presenter: presenter
        ) == .denied)
        #expect(events.values == ["explanation", "request"])
        #expect(preferences.screenRecordingRequestMade)
    }

    @Test func disabledFirstLaunchDoesNothingAndExistingGrantSkipsOnboarding() {
        let preferences = AppPreferences(storage: MemoryPreferences())
        let service = FakePermissionService(preflightResult: false)
        let presenter = FakeOnboardingPresenter(choice: .continue)
        let controller = ScreenRecordingPermissionController(
            service: service,
            preferences: preferences,
            urlOpener: FakeURLOpener()
        )
        _ = controller.runFirstLaunchOnboardingIfNeeded(enabled: false, presenter: presenter)
        #expect(presenter.presentCount == 0)
        #expect(service.requestCount == 0)

        service.preflightResult = true
        #expect(controller.refresh() == .granted)
        _ = controller.runFirstLaunchOnboardingIfNeeded(enabled: true, presenter: presenter)
        #expect(presenter.presentCount == 0)
    }

    @Test func settingsFallsBackToPrivacyRoot() {
        let opener = FakeURLOpener(results: [false, true])
        let controller = ScreenRecordingPermissionController(
            service: FakePermissionService(),
            preferences: AppPreferences(storage: MemoryPreferences()),
            urlOpener: opener
        )
        #expect(controller.openSettings())
        #expect(opener.opened == [
            ScreenRecordingPermissionController.settingsURL,
            ScreenRecordingPermissionController.privacyRootURL,
        ])
    }

    @Test func loginControllerNeverRegistersAtInitializationAndReconcilesTruth() {
        let preferences = AppPreferences(storage: MemoryPreferences())
        preferences.launchAtLogin = true
        let service = FakeLoginService(status: .disabled)
        let controller = LaunchAtLoginController(
            service: service,
            preferences: preferences,
            urlOpener: FakeURLOpener()
        )
        #expect(controller.state == .disabled)
        #expect(service.registerCount == 0)
        #expect(!preferences.launchAtLogin)
    }

    @Test func loginChangesOnlyOnUserActionAndApprovalIsActionable() {
        let preferences = AppPreferences(storage: MemoryPreferences())
        let service = FakeLoginService(status: .disabled)
        service.statusAfterRegister = .requiresUserApproval
        let opener = FakeURLOpener(results: [true])
        let controller = LaunchAtLoginController(
            service: service,
            preferences: preferences,
            urlOpener: opener
        )

        #expect(controller.setEnabled(true) == .requiresUserApproval)
        #expect(service.registerCount == 1)
        #expect(preferences.launchAtLogin)
        #expect(controller.openSettings())
        #expect(opener.opened == [LaunchAtLoginController.settingsURL])
    }

    @Test func loginFailureRestoresActualServiceState() {
        let preferences = AppPreferences(storage: MemoryPreferences())
        let service = FakeLoginService(status: .disabled)
        service.registerError = TestFailure.expected
        let controller = LaunchAtLoginController(
            service: service,
            preferences: preferences,
            urlOpener: FakeURLOpener()
        )
        #expect(controller.setEnabled(true) == .disabled)
        #expect(controller.lastErrorDescription != nil)
        #expect(!preferences.launchAtLogin)
    }
}

private final class EventLog: @unchecked Sendable {
    var values: [String] = []
}

private final class FakePermissionService: ScreenRecordingPermissionServicing,
    @unchecked Sendable
{
    var preflightResult: Bool
    var requestResult: Bool
    var requestCount = 0
    let events: EventLog?

    init(
        preflightResult: Bool = false,
        requestResult: Bool = false,
        events: EventLog? = nil
    ) {
        self.preflightResult = preflightResult
        self.requestResult = requestResult
        self.events = events
    }

    func preflight() -> Bool { preflightResult }
    func request() -> Bool {
        requestCount += 1
        events?.values.append("request")
        return requestResult
    }
}

private final class FakeOnboardingPresenter: ScreenRecordingOnboardingPresenting {
    let choice: ScreenRecordingOnboardingChoice
    var presentCount = 0
    let events: EventLog?

    init(choice: ScreenRecordingOnboardingChoice, events: EventLog? = nil) {
        self.choice = choice
        self.events = events
    }

    func presentExplanation() -> ScreenRecordingOnboardingChoice {
        presentCount += 1
        events?.values.append("explanation")
        return choice
    }
}

private final class FakeURLOpener: ExternalURLOpening {
    var results: [Bool]
    var opened: [URL] = []

    init(results: [Bool] = []) { self.results = results }
    func open(_ url: URL) -> Bool {
        opened.append(url)
        return results.isEmpty ? false : results.removeFirst()
    }
}

private enum TestFailure: Error { case expected }

private final class FakeLoginService: LaunchAtLoginServicing, @unchecked Sendable {
    var currentStatus: LaunchAtLoginServiceStatus
    var statusAfterRegister: LaunchAtLoginServiceStatus?
    var statusAfterUnregister: LaunchAtLoginServiceStatus?
    var registerError: Error?
    var unregisterError: Error?
    var registerCount = 0
    var unregisterCount = 0

    init(status: LaunchAtLoginServiceStatus) { currentStatus = status }
    var status: LaunchAtLoginServiceStatus { currentStatus }
    func register() throws {
        registerCount += 1
        if let registerError { throw registerError }
        if let statusAfterRegister { currentStatus = statusAfterRegister }
    }
    func unregister() throws {
        unregisterCount += 1
        if let unregisterError { throw unregisterError }
        if let statusAfterUnregister { currentStatus = statusAfterUnregister }
    }
}
