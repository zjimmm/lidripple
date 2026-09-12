import AppKit
import Foundation
import LidRippleCore

/// Composition seam implemented by the app coordinator. It suspends live input,
/// tears down capture, and asks the sole overlay presenter to install only its
/// in-memory synthetic source.
@MainActor
public protocol DebugScrubberSession: AnyObject {
    func prepareDebugSession(intensity: Double) async throws
    func updateDebugProgress(_ progress: Double, direction: Double)
    func updateDebugIntensity(_ intensity: Double)
    func finishDebugSession() async
}

@MainActor
public protocol DebugPlaybackCancellation: AnyObject {
    func cancel()
}

@MainActor
public protocol DebugPlaybackScheduling: AnyObject {
    func schedule(
        interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any DebugPlaybackCancellation
}

@MainActor
public final class RunLoopDebugPlaybackScheduler: DebugPlaybackScheduling {
    public init() {}

    public func schedule(
        interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any DebugPlaybackCancellation {
        let token = TimerCancellation()
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { action() }
        }
        token.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        return token
    }
}

@MainActor
private final class TimerCancellation: DebugPlaybackCancellation {
    var timer: Timer?

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

@MainActor
public final class DebugScrubberController: NSObject, NSWindowDelegate {
    public private(set) var isOpen = false
    public private(set) var isPlaying = false
    public private(set) var progress = 0.0
    public private(set) var direction = 1.0

    private let session: any DebugScrubberSession
    private let scheduler: any DebugPlaybackScheduling
    private let now: () -> TimeInterval
    private let maximumProgress: Double
    private let playbackDuration: TimeInterval
    private let presentsPanel: Bool
    private let reportError: (String) -> Void

    private var panel: NSPanel?
    private var slider: NSSlider?
    private var progressLabel: NSTextField?
    private var playback: (any DebugPlaybackCancellation)?
    private var lastTick = 0.0
    private var isOpening = false
    private var generation: UInt64 = 0

    public init(
        session: any DebugScrubberSession,
        scheduler: (any DebugPlaybackScheduling)? = nil,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        maximumProgress: Double = FoldTuning.default.maxProgress,
        playbackDuration: TimeInterval = 1.2,
        presentsPanel: Bool = true,
        reportError: @escaping (String) -> Void = { _ in }
    ) {
        self.session = session
        self.scheduler = scheduler ?? RunLoopDebugPlaybackScheduler()
        self.now = now
        self.maximumProgress = max(maximumProgress, 1)
        self.playbackDuration = max(playbackDuration, 0.001)
        self.presentsPanel = presentsPanel
        self.reportError = reportError
        super.init()
    }

    public func open(intensity: Double) async {
        guard !isOpen, !isOpening else { return }
        isOpening = true
        generation &+= 1
        let cycle = generation

        do {
            try await session.prepareDebugSession(
                intensity: AppPreferences.clampIntensity(intensity)
            )
        } catch {
            guard generation == cycle else { return }
            isOpening = false
            reportError("Unable to open the debug scrubber: \(error)")
            return
        }

        guard generation == cycle, isOpening else {
            // close()/restriction already tore down the owning session. A
            // stale preparation must not finish a newer session after unlock.
            return
        }

        isOpening = false
        progress = 0
        direction = 1
        isOpen = true
        session.updateDebugProgress(0, direction: 1)
        if presentsPanel { presentPanel() }
    }

    public func close() async {
        guard isOpen || isOpening else { return }
        abortForSystemRestriction()
        await session.finishDebugSession()
    }

    /// Cancels a pending open or playback before returning to the notification
    /// handler. The owner must synchronously hide its separate overlay too.
    public func abortForSystemRestriction() {
        generation &+= 1
        isOpening = false
        stopPlayback()
        panel?.orderOut(nil)
        panel = nil
        slider = nil
        progressLabel = nil
        isOpen = false
    }

    public func setProgress(_ value: Double) {
        guard isOpen else { return }
        stopPlayback()
        let clamped = min(max(value, 0), maximumProgress)
        direction = clamped >= progress ? 1 : -1
        progress = clamped
        applyProgress()
    }

    public func playForward() { startPlayback(direction: 1) }
    public func playReverse() { startPlayback(direction: -1) }

    public func reset() {
        guard isOpen else { return }
        stopPlayback()
        progress = 0
        direction = 1
        applyProgress()
    }

    public func setIntensity(_ value: Double) {
        guard isOpen else { return }
        session.updateDebugIntensity(AppPreferences.clampIntensity(value))
    }

    /// Deterministic tick seam used by the injected scheduler in tests.
    public func tick(now currentTime: TimeInterval) {
        guard isOpen, isPlaying else { return }
        let delta = min(max(currentTime - lastTick, 0), 1.0 / 15.0)
        lastTick = currentTime
        progress = min(
            max(progress + direction * delta * maximumProgress / playbackDuration, 0),
            maximumProgress
        )
        applyProgress()
        if progress == 0 || progress == maximumProgress { stopPlayback() }
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        Task { @MainActor [weak self] in await self?.close() }
        return false
    }

    private func startPlayback(direction: Double) {
        guard isOpen else { return }
        stopPlayback()
        self.direction = direction
        lastTick = now()
        isPlaying = true
        playback = scheduler.schedule(interval: 1.0 / 60.0) { [weak self] in
            guard let self else { return }
            self.tick(now: self.now())
        }
    }

    private func stopPlayback() {
        playback?.cancel()
        playback = nil
        isPlaying = false
    }

    private func applyProgress() {
        slider?.doubleValue = progress
        progressLabel?.stringValue = String(format: "p = %.3f", progress)
        session.updateDebugProgress(progress, direction: direction)
    }

    private func presentPanel() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 154),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "lidripple Debug Scrubber"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.delegate = self
        panel.center()

        let slider = NSSlider(
            value: progress,
            minValue: 0,
            maxValue: maximumProgress,
            target: self,
            action: #selector(sliderChanged)
        )
        slider.frame = NSRect(x: 20, y: 96, width: 410, height: 24)
        slider.isContinuous = true
        slider.setAccessibilityLabel("Fold progress")

        let fold = NSButton(title: "Play Fold", target: self, action: #selector(playFold))
        fold.frame = NSRect(x: 20, y: 52, width: 100, height: 30)
        let reverse = NSButton(
            title: "Reverse",
            target: self,
            action: #selector(playUnfold)
        )
        reverse.frame = NSRect(x: 128, y: 52, width: 100, height: 30)
        let reset = NSButton(title: "Reset", target: self, action: #selector(resetPressed))
        reset.frame = NSRect(x: 236, y: 52, width: 84, height: 30)
        let close = NSButton(title: "Close", target: self, action: #selector(closePressed))
        close.frame = NSRect(x: 328, y: 52, width: 102, height: 30)

        let label = NSTextField(labelWithString: String(format: "p = %.3f", progress))
        label.frame = NSRect(x: 20, y: 18, width: 410, height: 20)
        label.alignment = .right

        panel.contentView?.addSubview(slider)
        panel.contentView?.addSubview(fold)
        panel.contentView?.addSubview(reverse)
        panel.contentView?.addSubview(reset)
        panel.contentView?.addSubview(close)
        panel.contentView?.addSubview(label)
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        self.slider = slider
        progressLabel = label
    }

    @objc private func sliderChanged(_ sender: NSSlider) { setProgress(sender.doubleValue) }
    @objc private func playFold() { playForward() }
    @objc private func playUnfold() { playReverse() }
    @objc private func resetPressed() { reset() }
    @objc private func closePressed() {
        Task { @MainActor [weak self] in await self?.close() }
    }
}
