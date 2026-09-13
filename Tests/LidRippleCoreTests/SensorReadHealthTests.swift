import Testing
@testable import LidRippleSensor

@Test func sensorReadHealthIgnoresTransientMissesAndReportsOnceAtThreshold() {
    var health = SensorReadHealth(failureThreshold: 3)

    var didReport = health.record(success: false)
    #expect(!didReport)
    didReport = health.record(success: false)
    #expect(!didReport)
    didReport = health.record(success: true)
    #expect(!didReport)
    #expect(health.consecutiveFailures == 0)
    didReport = health.record(success: false)
    #expect(!didReport)
    didReport = health.record(success: false)
    #expect(!didReport)
    didReport = health.record(success: false)
    #expect(didReport)
    didReport = health.record(success: false)
    #expect(!didReport)
    #expect(health.didReportUnavailable)
}
