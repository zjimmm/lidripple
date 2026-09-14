import AppKit
import Foundation
import LidRippleCore

/// Composition seam implemented by the app coordinator. It suspends live input,
/// tears down capture, and asks the sole overlay presenter to install only its
/// in-memory synthetic source.
@MainActor
public protocol DebugScrubberSession: AnyObject {
    var previewEffect: DesktopEffect { get }
    func selectPreviewEffect(_ effect: DesktopEffect)
    func prepareDebugSession(intensity: Double) async throws
    func updateDebugProgress(_ progress: Double, direction: Double)
    func updateDebugIntensity(_ intensity: Double)
    func finishDebugSession() async
}

public extension DebugScrubberSession {
    var previewEffect: DesktopEffect { .fold }
    func selectPreviewEffect(_ effect: DesktopEffect) {}
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
        // Use the same display-synchronized clock as physical lid playback.
        // A free-running Timer drifts against drawable presentation deadlines.
        PreviewClockCancellation(RunLoopAppAnimationScheduler().schedule(
            interval: interval, action: action
        ))
    }
}

@MainActor
private final class PreviewClockCancellation: DebugPlaybackCancellation {
    private let clock: any AppAnimationCancellation
    init(_ clock: any AppAnimationCancellation) { self.clock = clock }
    func cancel() { clock.cancel() }
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
    private var playbackStart = 0.0
    private var playbackElapsed = 0.0
    private var playbackSpan = 1.0
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
            reportError("Unable to preview the effect: \(error)")
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
        guard isOpen, value.isFinite else { return }
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
        guard isOpen, isPlaying, currentTime.isFinite, currentTime > lastTick else { return }
        let delta = min(max(currentTime - lastTick, 0), 1.0 / 15.0)
        lastTick = currentTime
        playbackElapsed += delta
        let t = min(playbackElapsed / playbackSpan, 1)
        let eased = t * t * (3 - 2 * t)
        let target = direction > 0 ? maximumProgress : 0
        progress = playbackStart + (target - playbackStart) * eased
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
        playbackStart = progress
        playbackElapsed = 0
        let distance = direction > 0 ? maximumProgress - progress : progress
        playbackSpan = max(playbackDuration * distance / maximumProgress, 0.001)
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
        progressLabel?.stringValue = "Lid closed: \(Int(min(progress, 1) * 100))% · Sample artwork, not your screen"
        session.updateDebugProgress(progress, direction: direction)
    }

    private func presentPanel() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 200),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "LidRipple · Effect Preview"
        // The preview overlay sits at shielding level. Controls must remain
        // visible and escapable above it even at the fully sealed endpoint.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.delegate = self
        panel.center()

        let effects = NSSegmentedControl(labels: DesktopEffect.allCases.map(\.title),
            trackingMode: .selectOne, target: self, action: #selector(effectChanged(_:)))
        effects.frame = NSRect(x: 20, y: 149, width: 410, height: 28)
        effects.selectedSegment = DesktopEffect.allCases.firstIndex(of: session.previewEffect) ?? 0
        effects.setAccessibilityLabel("Preview effect")
        panel.contentView?.addSubview(effects)

        let slider = NSSlider(
            value: progress,
            minValue: 0,
            maxValue: maximumProgress,
            target: self,
            action: #selector(sliderChanged)
        )
        slider.frame = NSRect(x: 20, y: 96, width: 410, height: 24)
        slider.isContinuous = true
        slider.setAccessibilityLabel("Lid closing progress")

        let fold = NSButton(title: "Close Lid", target: self, action: #selector(playFold))
        fold.frame = NSRect(x: 20, y: 52, width: 100, height: 30)
        let reverse = NSButton(
            title: "Open Lid",
            target: self,
            action: #selector(playUnfold)
        )
        reverse.frame = NSRect(x: 128, y: 52, width: 100, height: 30)
        let reset = NSButton(title: "Reset", target: self, action: #selector(resetPressed))
        reset.frame = NSRect(x: 236, y: 52, width: 84, height: 30)
        let close = NSButton(title: "Done", target: self, action: #selector(closePressed))
        close.keyEquivalent = "\u{1b}"
        close.frame = NSRect(x: 328, y: 52, width: 102, height: 30)

        let label = NSTextField(labelWithString: "Lid closed: 0% · Sample artwork, not your screen")
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
    @objc private func effectChanged(_ sender: NSSegmentedControl) {
        guard DesktopEffect.allCases.indices.contains(sender.selectedSegment) else { return }
        session.selectPreviewEffect(DesktopEffect.allCases[sender.selectedSegment])
        applyProgress()
    }
    @objc private func playFold() { playForward() }
    @objc private func playUnfold() { playReverse() }
    @objc private func resetPressed() { reset() }
    @objc private func closePressed() {
        Task { @MainActor [weak self] in await self?.close() }
    }
}
