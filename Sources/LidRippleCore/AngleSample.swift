import Foundation

/// One reading from a lid angle source.
///
/// `degrees` is the physical lid angle: 0 is fully closed, and MacBook lids
/// open to roughly 135 degrees. `timestamp` is monotonic seconds from an
/// arbitrary origin; only differences between samples are meaningful.
public struct AngleSample: Equatable, Sendable {
    public let degrees: Double
    public let timestamp: TimeInterval

    public init(degrees: Double, timestamp: TimeInterval) {
        self.degrees = degrees
        self.timestamp = timestamp
    }
}
