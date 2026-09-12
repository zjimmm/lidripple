import AppKit
import CoreGraphics
import LidRippleCore
import LidRippleOverlay
import LidRippleRenderer

@MainActor
final class PreviewAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var overlayWindow: OverlayWindow?
    private var controlPanel: NSPanel?
    private var foldView: FoldMetalView?
    private var slider: NSSlider?
    private var statusLabel: NSTextField?
    private var playbackTimer: Timer?
    private var tuningTimer: Timer?
    private var playbackDirection = 1.0
    private var lastTick = 0.0
    private var tuningURL: URL?
    private var tuningModificationDate: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        do {
            try setUpPreview()
            setUpControls()
            setUpTuningReloadIfRequested()
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            print("Unable to start lidripple preview: \(error)")
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        playbackTimer?.invalidate()
        tuningTimer?.invalidate()
        foldView?.clearSource()
        overlayWindow?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === controlPanel { NSApp.terminate(nil) }
        return true
    }

    private func setUpPreview() throws {
        guard let screen = BuiltInDisplay.screen() else {
            throw PreviewError.builtInDisplayUnavailable
        }
        let scale = screen.backingScaleFactor
        let pixelWidth = max(Int((screen.frame.width * scale).rounded()), 1)
        let pixelHeight = max(Int((screen.frame.height * scale).rounded()), 1)
        let view = try FoldMetalView(
            frame: NSRect(origin: .zero, size: screen.frame.size)
        )
        guard let device = view.device else { throw RendererError.metalUnavailable }
        let source = try SyntheticFrame.makeCheckerboardGradientTexture(
            device: device,
            width: pixelWidth,
            height: pixelHeight
        )
        try view.setPreviewSource(source)
        view.update(FoldState(phase: .folding, progress: 0, velocity: 0))

        let window = OverlayWindow(screen: screen)
        window.contentView = view
        window.orderFrontRegardless()

        foldView = view
        overlayWindow = window
    }

    private func setUpControls() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 138),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "lidripple scrub preview"
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.delegate = self
        panel.center()

        let slider = NSSlider(
            value: 0,
            minValue: 0,
            maxValue: 1.06,
            target: self,
            action: #selector(sliderChanged)
        )
        slider.frame = NSRect(x: 20, y: 78, width: 390, height: 24)
        slider.isContinuous = true

        let play = NSButton(
            title: "Play fold",
            target: self,
            action: #selector(playForward)
        )
        play.frame = NSRect(x: 20, y: 34, width: 100, height: 30)

        let reverse = NSButton(
            title: "Reverse",
            target: self,
            action: #selector(playReverse)
        )
        reverse.frame = NSRect(x: 128, y: 34, width: 100, height: 30)

        let status = NSTextField(labelWithString: "p = 0.000")
        status.frame = NSRect(x: 244, y: 39, width: 166, height: 20)
        status.alignment = .right

        panel.contentView?.addSubview(slider)
        panel.contentView?.addSubview(play)
        panel.contentView?.addSubview(reverse)
        panel.contentView?.addSubview(status)
        panel.makeKeyAndOrderFront(nil)

        self.slider = slider
        statusLabel = status
        controlPanel = panel
    }

    private func setUpTuningReloadIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["LIDRIPPLE_TUNING_FILE"] else {
            return
        }
        tuningURL = URL(fileURLWithPath: path)
        reloadTuningIfChanged()

        let timer = Timer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(tuningTick),
            userInfo: nil,
            repeats: true
        )
        tuningTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        stopPlayback()
        applyProgress(sender.doubleValue, direction: sender.doubleValue >= (foldView?.progress ?? 0) ? 1 : -1)
    }

    @objc private func playForward() {
        startPlayback(direction: 1)
    }

    @objc private func playReverse() {
        startPlayback(direction: -1)
    }

    @objc private func playbackTick(_ timer: Timer) {
        let now = ProcessInfo.processInfo.systemUptime
        let delta = min(max(now - lastTick, 0), 1.0 / 15.0)
        lastTick = now
        let current = slider?.doubleValue ?? 0
        let next = min(max(current + playbackDirection * delta / 1.2, 0), 1.06)
        slider?.doubleValue = next
        applyProgress(next, direction: playbackDirection)
        if next == 0 || next == 1.06 { stopPlayback() }
    }

    @objc private func tuningTick(_ timer: Timer) {
        reloadTuningIfChanged()
    }

    private func startPlayback(direction: Double) {
        stopPlayback()
        playbackDirection = direction
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(playbackTick),
            userInfo: nil,
            repeats: true
        )
        playbackTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopPlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func applyProgress(_ progress: Double, direction: Double) {
        let phase: FoldPhase
        if progress >= 1 { phase = .sealed }
        else { phase = direction < 0 ? .unfolding : .folding }
        foldView?.update(FoldState(phase: phase, progress: progress, velocity: direction))
        statusLabel?.stringValue = String(format: "p = %.3f", progress)
    }

    private func reloadTuningIfChanged() {
        guard let tuningURL else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: tuningURL.path)
            let modificationDate = attributes[.modificationDate] as? Date
            guard modificationDate != tuningModificationDate else { return }
            let tuning = try FoldTuning.loading(overridesAt: tuningURL)
            foldView?.updateTuning(tuning)
            tuningModificationDate = modificationDate
            statusLabel?.textColor = .labelColor
        } catch {
            statusLabel?.textColor = .systemRed
            statusLabel?.stringValue = "Tuning error: \(error)"
        }
    }
}

private enum PreviewError: Error {
    case builtInDisplayUnavailable
}
