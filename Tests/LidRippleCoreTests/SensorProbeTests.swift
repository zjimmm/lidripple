import Testing
import Foundation
@testable import LidRippleSensor
@testable import LidRippleCore

@Test func probeReportsWithoutCrashingOnAnyHardware() {
    let report = SensorProbe.probe()
    #expect(report.vendorID == 0x05AC)
    #expect(report.productID == 0x8104)
    #expect(!report.description.isEmpty)
}

@Test func isAvailableNeverThrowsAndMatchesProbe() {
    let source = HIDAngleSource()
    #expect(source.isAvailable == SensorProbe.probe().isPresent)
}

@Test func startOnASensorlessMachineThrowsDeviceNotFound() throws {
    let source = HIDAngleSource()
    guard !source.isAvailable else { return }  // sensor-equipped machine: nothing to assert here
    #expect(throws: HIDAngleSourceError.deviceNotFound) {
        try source.start { _ in }
    }
}

@Test func stopIsSafeWhenNeverStarted() {
    HIDAngleSource().stop()  // must not crash
}
