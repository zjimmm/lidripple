import Foundation
import IOKit
import IOKit.hid
import LidRippleCore

public enum HIDAngleSourceError: Error, Equatable {
    case deviceNotFound
    case elementNotFound
    case openFailed(Int32)
    case alreadyStarted
}

/// Reads the internal lid angle sensor by polling its HID element.
///
/// Polling rather than an input-report callback is deliberate: the sensor does
/// not push reports on change, so a value read on a timer is the only way to
/// get a steady cadence.
public final class HIDAngleSource: LidAngleSource, @unchecked Sendable {
    /// HID report ID for the angle Feature report, per the reference
    /// implementation cited by the spec (github.com/samhenrigold/LidAngleSensor).
    private static let angleReportID: CFIndex = 1
    /// Buffer size for `IOHIDDeviceGetReport`; the angle value only needs the
    /// first 3 bytes, but this matches the reference implementation's buffer.
    private static let reportBufferSize = 8

    private let pollHz: Double
    private let rawToDegrees: Double
    private let queue = DispatchQueue(label: "com.lidripple.sensor", qos: .userInteractive)

    /// Guards `device` and `timer` against concurrent access between the
    /// timer's event handler (which runs on `queue`) and `start()`/`stop()`
    /// calls, which may run on any thread.
    ///
    /// This is a plain lock rather than `queue.sync` deliberately: the
    /// `LidAngleSource` protocol documents that the sample handler passed to
    /// `start()` "may be called on any thread," and that handler is in fact
    /// invoked from inside the timer's event handler *on* `queue` (see
    /// `start()` below). Nothing prevents a caller from calling `stop()`
    /// synchronously from within that handler; `queue.sync` invoked from
    /// `queue` itself would deadlock in that case. A lock has no such
    /// self-deadlock hazard, since it is never held while calling into the
    /// caller-supplied handler — only around the direct reads/writes of
    /// `device`/`timer` and the IOKit calls that open/read/close the device,
    /// which is exactly the section that must not overlap between a
    /// concurrent `read()` and `stop()`. (Verified: nothing in this codebase
    /// currently calls `stop()` from inside a `start()` handler, but the
    /// public API contract doesn't forbid a future caller from doing so.)
    private let stateLock = NSLock()
    private var device: IOHIDDevice?
    private var timer: DispatchSourceTimer?

    /// - Parameters:
    ///   - pollHz: sample cadence. Spec section 4 specifies 60 Hz.
    ///   - rawToDegrees: scale from the sensor's 16-bit integer to degrees.
    ///     Provisionally 1.0 (unscaled), per the reference implementation at
    ///     github.com/samhenrigold/LidAngleSensor (which lists this exact
    ///     machine, Mac16,12, as supported) — NOT yet verified with a
    ///     physical lid sweep on this unit. Do not treat as confirmed until
    ///     a human checks it against known lid angles (Task 2, Step 6).
    public init(pollHz: Double = 60, rawToDegrees: Double = 1.0) {
        self.pollHz = pollHz
        self.rawToDegrees = rawToDegrees
    }

    public var isAvailable: Bool { SensorProbe.matchingDevice() != nil }

    public func start(_ handler: @escaping @Sendable (AngleSample) -> Void) throws {
        stateLock.lock()
        let isRunning = timer != nil
        stateLock.unlock()
        guard !isRunning else { throw HIDAngleSourceError.alreadyStarted }
        let candidates = SensorProbe.matchingDevices()
        guard !candidates.isEmpty else { throw HIDAngleSourceError.deviceNotFound }

        // Vendor/product ID plus usage page/usage still isn't always enough
        // to land on exactly one device on Apple's Sensor Platform Unit
        // (observed on this Mac16,12: matching sometimes still returns a
        // sibling endpoint, e.g. the accelerometer, that shares all four
        // values). So each candidate is opened and validated by actually
        // requesting a Feature report; the first one that responds is kept,
        // and the rest are closed. This mirrors the approach in the
        // reference implementation cited by the spec
        // (github.com/samhenrigold/LidAngleSensor).
        var validated: IOHIDDevice?
        var anyOpened = false
        var lastOpenStatus: IOReturn = kIOReturnSuccess
        for candidate in candidates {
            let status = IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
            guard status == kIOReturnSuccess else {
                lastOpenStatus = status
                continue
            }
            anyOpened = true
            if Self.readRawValue(from: candidate) != nil {
                validated = candidate
                break
            }
            IOHIDDeviceClose(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        guard let device = validated else {
            // Not "no HID element matched" anymore (that's what this case
            // originally meant, back when matching used
            // IOHIDDeviceCopyMatchingElements/IOHIDDeviceGetValue) — it now
            // means at least one candidate device opened successfully, but
            // none of them returned a valid report when probed. See
            // task-2-report.md for the investigation behind this.
            throw anyOpened ? HIDAngleSourceError.elementNotFound : HIDAngleSourceError.openFailed(lastOpenStatus)
        }

        let interval = 1.0 / pollHz
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        source.setEventHandler { [weak self] in
            guard let self, let sample = self.read() else { return }
            handler(sample)
        }

        stateLock.lock()
        self.device = device
        self.timer = source
        stateLock.unlock()

        source.resume()
    }

    public func stop() {
        // Held for the full close, not just the property mutation: this is
        // what actually prevents `read()` (which holds the same lock for its
        // full IOHIDDeviceGetReport call) from ever observing a device
        // that's mid-close or already closed.
        stateLock.lock()
        defer { stateLock.unlock() }
        timer?.cancel()
        timer = nil
        if let device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        device = nil
    }

    /// Reads a Feature report directly rather than going through
    /// `IOHIDDeviceCopyMatchingElements`/`IOHIDDeviceGetValue`: on this
    /// hardware, the element matched by usage page 0x0020 / usage 0x008A is
    /// the wrapping HID *Collection*, not a scalar Input element, so
    /// `IOHIDDeviceGetValue` on it always fails with kIOReturnBadArgument.
    /// This matches the approach in the reference implementation cited by
    /// the spec (github.com/samhenrigold/LidAngleSensor, HardwareCompat.swift
    /// / LidAngleSensor.swift): report ID 1, Feature type, 8-byte buffer,
    /// little-endian UInt16 angle at bytes 1-2.
    private static func readRawValue(from device: IOHIDDevice) -> UInt16? {
        var buffer = [UInt8](repeating: 0, count: reportBufferSize)
        var length = CFIndex(buffer.count)
        let status = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, angleReportID, &buffer, &length)
        guard status == kIOReturnSuccess, length >= 3 else { return nil }
        return UInt16(buffer[2]) << 8 | UInt16(buffer[1])
    }

    /// Locked for its full duration (including the blocking
    /// `IOHIDDeviceGetReport` call inside `readRawValue`) so a concurrent
    /// `stop()` can never close the device mid-read; see `stateLock`'s doc
    /// comment for why this is a lock rather than `queue.sync`.
    private func read() -> AngleSample? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let device, let rawValue = Self.readRawValue(from: device) else { return nil }
        let degrees = Double(rawValue) * rawToDegrees
        return AngleSample(degrees: degrees, timestamp: ProcessInfo.processInfo.systemUptime)
    }
}
