import AppKit
import Foundation
import ServiceManagement

public enum LaunchAtLoginServiceStatus: Equatable, Sendable {
    case enabled
    case disabled
    case requiresUserApproval
    case unavailable(String)
}

public protocol LaunchAtLoginServicing: Sendable {
    var status: LaunchAtLoginServiceStatus { get }
    func register() throws
    func unregister() throws
}

public struct MainAppLaunchAtLoginService: LaunchAtLoginServicing {
    public init() {}

    public var status: LaunchAtLoginServiceStatus {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .disabled
        case .requiresApproval: return .requiresUserApproval
        case .notFound: return .unavailable("The installed application could not be found.")
        @unknown default: return .unavailable("The login item status is unknown.")
        }
    }

    public func register() throws { try SMAppService.mainApp.register() }
    public func unregister() throws { try SMAppService.mainApp.unregister() }
}

@MainActor
public final class LaunchAtLoginController {
    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    )!

    public private(set) var state: LaunchAtLoginServiceStatus
    public private(set) var lastErrorDescription: String?

    private let service: any LaunchAtLoginServicing
    private let preferences: AppPreferences
    private let urlOpener: any ExternalURLOpening

    public init(
        service: any LaunchAtLoginServicing = MainAppLaunchAtLoginService(),
        preferences: AppPreferences,
        urlOpener: (any ExternalURLOpening)? = nil
    ) {
        self.service = service
        self.preferences = preferences
        self.urlOpener = urlOpener ?? WorkspaceURLOpener()
        state = service.status
        reconcilePreference()
    }

    @discardableResult
    public func refresh() -> LaunchAtLoginServiceStatus {
        state = service.status
        reconcilePreference()
        return state
    }

    /// Registration changes happen only in response to this explicit user action.
    @discardableResult
    public func setEnabled(_ enabled: Bool) -> LaunchAtLoginServiceStatus {
        lastErrorDescription = nil
        do {
            if enabled { try service.register() } else { try service.unregister() }
        } catch {
            lastErrorDescription = String(describing: error)
        }
        state = service.status
        reconcilePreference()
        return state
    }

    @discardableResult
    public func openSettings() -> Bool { urlOpener.open(Self.settingsURL) }

    private func reconcilePreference() {
        switch state {
        case .enabled:
            preferences.launchAtLogin = true
        case .disabled:
            preferences.launchAtLogin = false
        case .requiresUserApproval:
            // Approval means a prior enable action is pending in System Settings.
            preferences.launchAtLogin = true
        case .unavailable:
            // Preserve intent while unavailable, but the menu reflects service truth.
            break
        }
    }
}
