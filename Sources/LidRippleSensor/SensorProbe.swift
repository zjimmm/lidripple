import Foundation
import IOKit
import IOKit.hid

/// Hardware identifiers for Apple's internal lid angle sensor.
///
/// Documented in spec section 4: Apple vendor 0x05AC, product 0x8104,
/// HID sensor page 0x0020, orientation usage 0x008A.
public enum LidSensorIdentifiers {
    public static let vendorID = 0x05AC
    public static let productID = 0x8104
    public static let usagePage = 0x0020
    public static let usage = 0x008A
}

/// Non-invasive presence check. Must never prompt the user.
public enum SensorProbe {
    public struct Report: Sendable {
        public let isPresent: Bool
        public let vendorID: Int
        public let productID: Int
        public let description: String
    }

    public static func probe() -> Report {
        let present = matchingDevice() != nil
        let description = present
            ? "Lid angle sensor found (vendor 0x05AC, product 0x8104)."
            : """
              No lid angle sensor found. This is expected on desktop Macs and on \
              several M1/M2 MacBook Air and 13-inch MacBook Pro configurations. \
              lidripple will use the timed fallback driver.
              """
        return Report(
            isPresent: present,
            vendorID: LidSensorIdentifiers.vendorID,
            productID: LidSensorIdentifiers.productID,
            description: description
        )
    }

    /// Returns the matched device, or nil. Opens the *manager* but never the
    /// device, which is what keeps this from triggering a permission prompt.
    ///
    /// Vendor/product ID plus usage page/usage narrows the match a great deal,
    /// but on Apple's Sensor Platform Unit multiple physically distinct
    /// endpoints (accelerometer, gyroscope, this angle sensor, etc.) can still
    /// share all four values, so more than one candidate may come back. This
    /// returns any one of them (`.first`); callers that need the specific
    /// responding device should use `matchingDevices()` and validate each
    /// candidate themselves, which is what `HIDAngleSource.start()` does.
    static func matchingDevice() -> IOHIDDevice? {
        matchingDevices().first
    }

    /// Returns every device matching vendor/product ID and usage page/usage.
    /// Opens the *manager* but never a device.
    static func matchingDevices() -> [IOHIDDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // "UsagePage"/"Usage" here are deliberately the bare-string keys
        // (kIOHIDElementUsagePageKey/kIOHIDElementUsageKey), NOT a typo for
        // Apple's documented *device*-matching keys
        // kIOHIDDeviceUsagePageKey/kIOHIDDeviceUsageKey ("DeviceUsagePage"/
        // "DeviceUsage") or the deprecated kIOHIDPrimaryUsagePageKey/
        // kIOHIDPrimaryUsageKey. IOHIDManagerSetDeviceMatching accepts these
        // bare keys for device-level filtering too, undocumented as such;
        // this was validated empirically against real Mac16,12 hardware
        // (see task-2-report.md) and matches the approach used by the
        // reference implementation cited by the spec
        // (github.com/samhenrigold/LidAngleSensor). Do not "correct" these
        // to the Device-prefixed constants — that silently breaks matching.
        let criteria: [String: Any] = [
            kIOHIDVendorIDKey: LidSensorIdentifiers.vendorID,
            kIOHIDProductIDKey: LidSensorIdentifiers.productID,
            "UsagePage": LidSensorIdentifiers.usagePage,
            "Usage": LidSensorIdentifiers.usage,
        ]
        IOHIDManagerSetDeviceMatching(manager, criteria as CFDictionary)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return Array(devices)
    }
}
