import Foundation

/// A stream of lid angle samples.
///
/// This protocol is the seam that keeps `FoldDriver` testable: the real
/// hardware source, a replayed trace, and a hand-built fake are
/// interchangeable behind it.
public protocol LidAngleSource: AnyObject, Sendable {
    /// Whether this source can actually produce samples on this machine.
    /// Checking must not prompt the user or open the device.
    var isAvailable: Bool { get }

    /// Begin delivering samples. The handler may be called on any thread.
    func start(_ handler: @escaping @Sendable (AngleSample) -> Void) throws

    /// Stop delivering samples. Safe to call when not started.
    func stop()
}
