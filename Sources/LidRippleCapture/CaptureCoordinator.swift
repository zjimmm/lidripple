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
            frame = try await session.latestFrame()
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
