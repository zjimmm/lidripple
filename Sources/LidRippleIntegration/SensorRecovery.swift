import Foundation

public enum SensorRecoveryOutcome: Equatable, Sendable {
    case recovered(attempts: Int)
    case fallbackRequired(attempts: Int)
}

/// Bounded retry policy for the HID service disappearing across sleep/wake.
/// The attempt closure stays on the main actor because production source
/// replacement is owned by AppDelegate; tests inject a no-wait sleeper.
public struct SensorRecovery: Sendable {
    public typealias Sleeper = @Sendable (Duration) async throws -> Void

    public let delays: [Duration]

    public init(
        delays: [Duration] = [
            .zero,
            .milliseconds(150),
            .milliseconds(350),
            .seconds(1),
        ]
    ) {
        precondition(!delays.isEmpty, "sensor recovery needs at least one attempt")
        self.delays = delays
    }

    public func run(
        attempt: @escaping @MainActor @Sendable () -> Bool,
        sleep: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) async throws -> SensorRecoveryOutcome {
        for (index, delay) in delays.enumerated() {
            try Task.checkCancellation()
            try await sleep(delay)
            try Task.checkCancellation()
            if await attempt() { return .recovered(attempts: index + 1) }
        }
        return .fallbackRequired(attempts: delays.count)
    }
}
