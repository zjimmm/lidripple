import CoreGraphics
import Metal

/// Owns the speculative capture lifecycle. Actor isolation makes every public
/// transition serial while generation checks close re-entrancy across async stream
/// startup and shutdown.
public actor CaptureCoordinator {
    public enum State: Equatable, Sendable {
        case idle
        case warming
        case frozen
    }

    private struct Target: Equatable, Sendable {
        let displayID: CGDirectDisplayID
        let excludedWindowID: CGWindowID
    }

    public private(set) var state: State = .idle
    public private(set) var frozenFrame: CapturedFrame?

    private let makeSession: CaptureSessionFactory
    private var target: Target?
    private var session: (any CaptureSession)?
    private var warmTask: Task<Void, any Error>?
    private var generation: UInt64 = 0

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw CaptureError.metalUnavailable
        }
        let deviceBox = MetalDeviceBox(device)
        makeSession = { displayID, excludedWindowID in
            ScreenCaptureSession(
                displayID: displayID,
                excludedWindowID: excludedWindowID,
                device: deviceBox.device
            )
        }
    }

    init(factory: @escaping CaptureSessionFactory) {
        makeSession = factory
    }

    public func warm(
        displayID: CGDirectDisplayID,
        excludingWindowID: CGWindowID
    ) async throws {
        let requested = Target(
            displayID: displayID,
            excludedWindowID: excludingWindowID
        )

        if state == .warming {
            guard target == requested else { throw CaptureError.conflictingWarmup }
            let currentGeneration = generation
            if let warmTask {
                try await warmTask.value
            }
            guard generation == currentGeneration, state != .idle else {
                throw CancellationError()
            }
            return
        }

        if state == .frozen {
            frozenFrame = nil
            state = .idle
        }

        generation &+= 1
        let currentGeneration = generation
        state = .warming
        target = requested

        let newSession: any CaptureSession
        do {
            newSession = try makeSession(displayID, excludingWindowID)
        } catch {
            clearCycle(ifGeneration: currentGeneration)
            throw error
        }

        session = newSession
        let task = Task { try await newSession.start() }
        warmTask = task

        do {
            try await task.value
        } catch {
            await newSession.stop()
            clearCycle(ifGeneration: currentGeneration)
            throw error
        }

        guard generation == currentGeneration else {
            await newSession.stop()
            throw CancellationError()
        }
        // A concurrent freeze may already have consumed this successfully started
        // session while this caller was waiting to resume on the actor.
        guard state == .warming else { return }
        warmTask = nil
    }

    public func freeze() async throws -> CapturedFrame {
        try await freeze(waitingUpTo: 0)
    }

    /// Freezes the newest complete frame, optionally waiting for the first frame
    /// after a cold stream start. The normal close path has already spent time in
    /// `.armed` and uses `freeze()`. Unlock has no warm band, so it uses a short
    /// bounded wait rather than racing the first ScreenCaptureKit callback.
    public func freeze(waitingUpTo timeout: TimeInterval) async throws -> CapturedFrame {
        guard state == .warming, let session else {
            throw CaptureError.notWarming
        }
        let currentGeneration = generation

        if let warmTask {
            do {
                try await warmTask.value
            } catch {
                await session.stop()
                clearCycle(ifGeneration: currentGeneration)
                throw error
            }
        }

        let frame: CapturedFrame?
        do {
            frame = try await newestFrame(
                from: session,
                waitingUpTo: max(timeout, 0),
                generation: currentGeneration
            )
        } catch {
            await session.stop()
            clearCycle(ifGeneration: currentGeneration)
            throw error
        }
        await session.stop()

        guard generation == currentGeneration, state == .warming else {
            throw CancellationError()
        }

        self.session = nil
        warmTask = nil
        target = nil
        guard let frame else {
            state = .idle
            throw CaptureError.noFrameAvailable
        }

        frozenFrame = frame
        state = .frozen
        return frame
    }

    private func newestFrame(
        from session: any CaptureSession,
        waitingUpTo timeout: TimeInterval,
        generation expectedGeneration: UInt64
    ) async throws -> CapturedFrame? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))

        while true {
            try Task.checkCancellation()
            guard generation == expectedGeneration, state == .warming else {
                throw CancellationError()
            }
            let frame = try await session.latestFrame()

            // `latestFrame()` is an actor/protocol suspension point. Reset, task
            // cancellation, or the deadline can all happen while it is in flight,
            // so validate the cycle again before accepting its result.
            try Task.checkCancellation()
            guard generation == expectedGeneration, state == .warming else {
                throw CancellationError()
            }

            let now = clock.now
            if let frame, timeout == 0 || now <= deadline { return frame }
            guard timeout > 0, now < deadline else { return nil }

            let remaining = now.duration(to: deadline)
            try await Task.sleep(for: min(.milliseconds(8), remaining))
        }
    }

    public func reset() async {
        generation &+= 1
        let activeSession = session
        session = nil
        warmTask = nil
        target = nil
        frozenFrame = nil
        state = .idle
        await activeSession?.stop()
    }

    private func clearCycle(ifGeneration expected: UInt64) {
        guard generation == expected else { return }
        session = nil
        warmTask = nil
        target = nil
        frozenFrame = nil
        state = .idle
    }
}

private final class MetalDeviceBox: @unchecked Sendable {
    let device: any MTLDevice

    init(_ device: any MTLDevice) {
        self.device = device
    }
}
