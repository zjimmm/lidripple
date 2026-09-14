import AppKit
import CoreGraphics
import Foundation

public enum ScreenRecordingPermissionState: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
}

public protocol ScreenRecordingPermissionServicing: Sendable {
    /// This check never displays a system prompt.
    func preflight() -> Bool
    /// This is the sole API in lidripple that may display the TCC prompt.
    func request() -> Bool
}

public struct SystemScreenRecordingPermissionService: ScreenRecordingPermissionServicing {
    public init() {}
    public func preflight() -> Bool { CGPreflightScreenCaptureAccess() }
    public func request() -> Bool { CGRequestScreenCaptureAccess() }
}

@MainActor
public protocol ExternalURLOpening: AnyObject {
    @discardableResult func open(_ url: URL) -> Bool
}

@MainActor
public final class WorkspaceURLOpener: ExternalURLOpening {
    public init() {}
    public func open(_ url: URL) -> Bool { NSWorkspace.shared.open(url) }
}

public enum ScreenRecordingOnboardingChoice: Equatable, Sendable {
    case `continue`
    case notNow
}

@MainActor
public protocol ScreenRecordingOnboardingPresenting: AnyObject {
    func presentExplanation() -> ScreenRecordingOnboardingChoice
}

/// Native, plain-language pre-prompt. Merely constructing it has no TCC side
/// effect; the system request remains behind the explicit Continue response.
@MainActor
public final class NativeScreenRecordingOnboardingPresenter:
    ScreenRecordingOnboardingPresenting
{
    public init() {}

    public func presentExplanation() -> ScreenRecordingOnboardingChoice {
        let alert = NSAlert()
        alert.messageText = "Allow Screen Recording for the fold effect?"
        alert.informativeText = """
        LidRipple briefly captures only the built-in display and excludes its own \
        overlay. It keeps one frame in GPU memory, writes nothing to disk, and sends \
        nothing over the network. It does not need Accessibility or Input Monitoring.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Not Now")
        return alert.runModal() == .alertFirstButtonReturn ? .continue : .notNow
    }
}

@MainActor
public final class ScreenRecordingPermissionController {
    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!
    public static let privacyRootURL = URL(
        string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
    )!

    public private(set) var state: ScreenRecordingPermissionState

    private let service: any ScreenRecordingPermissionServicing
    private let preferences: AppPreferences
    private let urlOpener: any ExternalURLOpening

    public init(
        service: any ScreenRecordingPermissionServicing =
            SystemScreenRecordingPermissionService(),
        preferences: AppPreferences,
        urlOpener: (any ExternalURLOpening)? = nil
    ) {
        self.service = service
        self.preferences = preferences
        self.urlOpener = urlOpener ?? WorkspaceURLOpener()
        state = Self.resolve(
            preflightGranted: service.preflight(),
            requestMade: preferences.screenRecordingRequestMade
        )
    }

    @discardableResult
    public func refresh() -> ScreenRecordingPermissionState {
        state = Self.resolve(
            preflightGranted: service.preflight(),
            requestMade: preferences.screenRecordingRequestMade
        )
        return state
    }

    /// Runs only on first enabled launch. Both choices are persisted so Not Now
    /// leaves a useful, non-nagging menu-bar app behind.
    @discardableResult
    public func runFirstLaunchOnboardingIfNeeded(
        enabled: Bool,
        presenter: any ScreenRecordingOnboardingPresenting
    ) -> ScreenRecordingPermissionState {
        guard enabled,
              state != .granted,
              !preferences.screenRecordingOnboardingCompleted
        else { return state }

        let choice = presenter.presentExplanation()
        preferences.screenRecordingOnboardingCompleted = true
        guard choice == .continue else { return state }
        return requestAfterExplanation()
    }

    /// Must only be called after the app's explanation or a direct menu action.
    @discardableResult
    public func requestAfterExplanation() -> ScreenRecordingPermissionState {
        preferences.screenRecordingRequestMade = true
        state = service.request() ? .granted : .denied
        return state
    }

    /// Tries the precise pane first, then the public Privacy & Security root.
    @discardableResult
    public func openSettings() -> Bool {
        urlOpener.open(Self.settingsURL) || urlOpener.open(Self.privacyRootURL)
    }

    public static func resolve(
        preflightGranted: Bool,
        requestMade: Bool
    ) -> ScreenRecordingPermissionState {
        if preflightGranted { return .granted }
        return requestMade ? .denied : .notDetermined
    }
}
