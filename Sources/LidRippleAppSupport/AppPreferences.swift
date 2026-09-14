import Foundation
import LidRippleCore

/// Minimal storage seam for product preferences. Tests use an in-memory store;
/// production uses `UserDefaults` through its existing API.
public protocol AppPreferencesStoring: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: AppPreferencesStoring {}

/// The complete persisted product state. Runtime fold/capture state and
/// diagnostics deliberately do not belong here.
@MainActor
public final class AppPreferences {
    public enum Key {
        public static let effect = "lidripple.effect"
        public static let enabled = "lidripple.enabled"
        public static let intensity = "lidripple.intensity"
        public static let launchAtLogin = "lidripple.launchAtLogin"
        public static let screenRecordingRequestMade = "lidripple.screenRecordingRequestMade"
        public static let screenRecordingOnboardingCompleted =
            "lidripple.screenRecordingOnboardingCompleted"
    }

    private let storage: any AppPreferencesStoring

    public var effect: DesktopEffect {
        get {
            DesktopEffect(rawValue: storage.object(forKey: Key.effect) as? String ?? "") ?? .fold
        }
        set { storage.set(newValue.rawValue, forKey: Key.effect) }
    }

    public init(storage: any AppPreferencesStoring = UserDefaults.standard) {
        self.storage = storage
        migrateIntensityIfNeeded()
    }

    public var isEnabled: Bool {
        get { bool(forKey: Key.enabled, default: true) }
        set { storage.set(newValue, forKey: Key.enabled) }
    }

    public var intensity: Double {
        get {
            guard let number = storage.object(forKey: Key.intensity) as? NSNumber else {
                return 1
            }
            return Self.clampIntensity(number.doubleValue)
        }
        set { storage.set(Self.clampIntensity(newValue), forKey: Key.intensity) }
    }

    /// User intent, reconciled against `SMAppService` truth at launch.
    public var launchAtLogin: Bool {
        get { bool(forKey: Key.launchAtLogin, default: false) }
        set { storage.set(newValue, forKey: Key.launchAtLogin) }
    }

    public var screenRecordingRequestMade: Bool {
        get { bool(forKey: Key.screenRecordingRequestMade, default: false) }
        set { storage.set(newValue, forKey: Key.screenRecordingRequestMade) }
    }

    /// Persists both Continue and Not Now so first-run explanation never nags.
    public var screenRecordingOnboardingCompleted: Bool {
        get { bool(forKey: Key.screenRecordingOnboardingCompleted, default: false) }
        set { storage.set(newValue, forKey: Key.screenRecordingOnboardingCompleted) }
    }

    nonisolated public static func clampIntensity(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, 0.5), 1)
    }

    private func bool(forKey key: String, default fallback: Bool) -> Bool {
        guard let number = storage.object(forKey: key) as? NSNumber else { return fallback }
        return number.boolValue
    }

    private func migrateIntensityIfNeeded() {
        guard let number = storage.object(forKey: Key.intensity) as? NSNumber else { return }
        let original = number.doubleValue
        let migrated = Self.clampIntensity(original)
        if original != migrated || !original.isFinite {
            storage.set(migrated, forKey: Key.intensity)
        }
    }
}
