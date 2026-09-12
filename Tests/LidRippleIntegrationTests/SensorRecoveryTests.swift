import Foundation
import Testing
@testable import LidRippleIntegration

@Suite(.serialized)
@MainActor
struct SensorRecoveryTests {
    @Test func succeedsOnEachPossibleAttemptAndPreservesDelayOrder() async throws {
        let delays: [Duration] = [.zero, .milliseconds(10), .milliseconds(20)]

        for successAttempt in 1...delays.count {
            let attempts = AttemptCounter(successOn: successAttempt)
            let sleeps = SleepRecorder()
            let recovery = SensorRecovery(delays: delays)

            let outcome = try await recovery.run(
                attempt: { attempts.tryOnce() },
                sleep: { await sleeps.record($0) }
            )

            #expect(outcome == .recovered(attempts: successAttempt))
            #expect(attempts.count == successAttempt)
            #expect(await sleeps.values == Array(delays.prefix(successAttempt)))
        }
    }

    @Test func exhaustionRequestsFallbackExactlyAfterTheBoundedAttempts() async throws {
        let attempts = AttemptCounter(successOn: nil)
        let recovery = SensorRecovery(delays: [.zero, .milliseconds(1), .milliseconds(2)])

        let outcome = try await recovery.run(
            attempt: { attempts.tryOnce() },
            sleep: { _ in }
        )

        #expect(outcome == .fallbackRequired(attempts: 3))
        #expect(attempts.count == 3)
    }

    @Test func cancellationStopsBeforeAnotherSourceOpenAttempt() async throws {
        let attempts = AttemptCounter(successOn: nil)
        let gate = SleepGate()
        let recovery = SensorRecovery(delays: [.zero, .seconds(1)])

        let task = Task {
            try await recovery.run(
                attempt: { attempts.tryOnce() },
                sleep: { await gate.sleep($0) }
            )
        }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.release()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(attempts.count == 0)
    }
}

@MainActor
private final class AttemptCounter {
    private let successOn: Int?
    private(set) var count = 0

    init(successOn: Int?) {
        self.successOn = successOn
    }

    func tryOnce() -> Bool {
        count += 1
        return count == successOn
    }
}

private actor SleepRecorder {
    private(set) var values: [Duration] = []
    func record(_ duration: Duration) { values.append(duration) }
}

private actor SleepGate {
    private var entered = false
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func sleep(_ duration: Duration) async {
        entered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}
