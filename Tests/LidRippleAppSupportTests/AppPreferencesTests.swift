import Foundation
import Testing
@testable import LidRippleAppSupport

@Suite(.serialized)
@MainActor
struct AppPreferencesTests {
    @Test func effectSelectionPersistsAndUnknownValuesFallBackToFold() {
        let store = MemoryPreferences()
        let preferences = AppPreferences(storage: store)
        #expect(preferences.effect == .fold)
        preferences.effect = .ripple
        #expect(AppPreferences(storage: store).effect == .ripple)
        store.set("unknown", forKey: AppPreferences.Key.effect)
        #expect(preferences.effect == .fold)
    }
    @Test func defaultsAreProductDefaultsAndContainNoRuntimeState() {
        let store = MemoryPreferences()
        let preferences = AppPreferences(storage: store)

        #expect(preferences.isEnabled)
        #expect(preferences.intensity == 1)
        #expect(!preferences.launchAtLogin)
        #expect(!preferences.screenRecordingRequestMade)
        #expect(!preferences.screenRecordingOnboardingCompleted)
        #expect(store.values.isEmpty)
    }

    @Test func valuesPersistAndIntensityClampsAtBothEndpoints() {
        let store = MemoryPreferences()
        let preferences = AppPreferences(storage: store)

        preferences.isEnabled = false
        preferences.intensity = 0.1
        preferences.launchAtLogin = true
        preferences.screenRecordingRequestMade = true
        preferences.screenRecordingOnboardingCompleted = true

        let restored = AppPreferences(storage: store)
        #expect(!restored.isEnabled)
        #expect(restored.intensity == 0.5)
        #expect(restored.launchAtLogin)
        #expect(restored.screenRecordingRequestMade)
        #expect(restored.screenRecordingOnboardingCompleted)

        restored.intensity = 8
        #expect(restored.intensity == 1)
        restored.intensity = .nan
        #expect(restored.intensity == 1)
    }

    @Test func invalidStoredIntensityIsMigrated() {
        let store = MemoryPreferences()
        store.set(-3.0, forKey: AppPreferences.Key.intensity)
        let preferences = AppPreferences(storage: store)
        #expect(preferences.intensity == 0.5)
        #expect(store.values[AppPreferences.Key.intensity] as? Double == 0.5)
    }
}

final class MemoryPreferences: AppPreferencesStoring {
    var values: [String: Any] = [:]
    func object(forKey defaultName: String) -> Any? { values[defaultName] }
    func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
}
