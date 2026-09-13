/// Converts transient poll misses into one service-loss signal. HID reads can
/// occasionally miss; recovery begins only after a bounded consecutive run.
struct SensorReadHealth: Equatable {
    let failureThreshold: Int
    private(set) var consecutiveFailures = 0
    private(set) var didReportUnavailable = false

    init(failureThreshold: Int) {
        precondition(failureThreshold > 0)
        self.failureThreshold = failureThreshold
    }

    mutating func record(success: Bool) -> Bool {
        if success {
            consecutiveFailures = 0
            return false
        }
        guard !didReportUnavailable else { return false }
        consecutiveFailures += 1
        if consecutiveFailures >= failureThreshold {
            didReportUnavailable = true
            return true
        }
        return false
    }
}
