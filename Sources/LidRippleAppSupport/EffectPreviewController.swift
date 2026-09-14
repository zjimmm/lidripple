import AppKit
import LidRippleCore

/// An illustrative, local-only preview. It never owns capture or live input.
@MainActor
final class EffectPreviewController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var animation: (any AppAnimationCancellation)?
    private var illustration: MacBookPreviewView?
    private var picker: NSSegmentedControl?
    var onSelect: (DesktopEffect) -> Void = { _ in }

    func show(effect: DesktopEffect) {
        if let panel {
            update(effect: effect)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "lidripple · Preview"
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let view = MacBookPreviewView(frame: NSRect(x: 0, y: 68, width: 480, height: 300))
        view.effect = effect
        panel.contentView?.addSubview(view)
        let picker = NSSegmentedControl(labels: ["Fold", "Ripple"], trackingMode: .selectOne,
            target: self, action: #selector(selectEffect(_:)))
        picker.frame = NSRect(x: 140, y: 34, width: 200, height: 26)
        picker.setAccessibilityLabel("Effect")
        panel.contentView?.addSubview(picker)
        let caption = NSTextField(labelWithString: "An illustration of the effect. Your desktop stays untouched.")
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        caption.alignment = .center
        caption.frame = NSRect(x: 12, y: 8, width: 456, height: 18)
        panel.contentView?.addSubview(caption)
        self.panel = panel
        self.picker = picker
        illustration = view
        update(effect: effect)
        let start = ProcessInfo.processInfo.systemUptime
        animation = RunLoopAppAnimationScheduler().schedule(interval: 1.0 / 60) { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            self.illustration?.progress = Self.progress(elapsed: ProcessInfo.processInfo.systemUptime - start)
        }
        panel.center()
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func update(effect: DesktopEffect) {
        illustration?.effect = effect
        picker?.selectedSegment = effect == .fold ? 0 : 1
    }

    func close() {
        animation?.cancel()
        animation = nil
        panel?.orderOut(nil)
        panel = nil
        illustration = nil
        picker = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { close(); return false }

    @objc private func selectEffect(_ sender: NSSegmentedControl) {
        let effect: DesktopEffect = sender.selectedSegment == 1 ? .ripple : .fold
        update(effect: effect)
        onSelect(effect)
    }

    /// Two eased movements with pauses at each endpoint; no seam at loop wrap.
    static func progress(elapsed: Double) -> Double {
        guard elapsed.isFinite, elapsed >= 0 else { return 0 }
        let time = elapsed.truncatingRemainder(dividingBy: 6)
        let t: Double
        if time < 0.8 { return 0 }
        if time < 2.8 { t = (time - 0.8) / 2 }
        else if time < 3.4 { return 1 }
        else if time < 5.4 { t = 1 - (time - 3.4) / 2 }
        else { return 0 }
        return t * t * (3 - 2 * t)
    }
}

@MainActor
private final class MacBookPreviewView: NSView {
    var effect: DesktopEffect = .fold { didSet { needsDisplay = true } }
    var progress = 0.0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let p = progress
        // The base stays fixed while the screen rotates down toward its hinge.
        let height = 174 * (1 - p) + 12
        let screen = NSRect(x: 102, y: 73, width: 276, height: height)
        NSColor.black.withAlphaComponent(0.1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 63, y: 35, width: 354, height: 18)).fill()
        NSColor(calibratedWhite: 0.23, alpha: 1).setFill()
        NSBezierPath(roundedRect: screen, xRadius: 9, yRadius: 9).fill()
        let display = screen.insetBy(dx: 7, dy: 6)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: display, xRadius: 4, yRadius: 4).addClip()
        NSGradient(starting: NSColor(calibratedRed: 0.08, green: 0.17, blue: 0.29, alpha: 1),
            ending: NSColor(calibratedRed: 0.86, green: 0.64, blue: 0.46, alpha: 1))?.draw(in: display, angle: 90)
        for ridge in 0..<5 {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: display.minX, y: display.minY))
            for step in 0...100 {
                let u = Double(step) / 100
                let wave = effect == .ripple
                    ? sin(u * 19 - p * 14 + Double(ridge)) * sin(p * .pi) * 0.075 : 0
                let fold = effect == .fold ? (1 - p * 0.8) : 1
                let v = (0.2 + Double(ridge) * 0.135 + 0.045 * sin(u * 7 + Double(ridge)) + wave) * fold
                path.line(to: NSPoint(x: display.minX + u * display.width,
                                     y: display.minY + v * display.height))
            }
            path.line(to: NSPoint(x: display.maxX, y: display.minY))
            path.close()
            NSColor(calibratedRed: 0.12 + Double(ridge) * 0.045,
                green: 0.23 + Double(ridge) * 0.038,
                blue: 0.32 + Double(ridge) * 0.047, alpha: 1).setFill()
            path.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let base = NSBezierPath()
        base.move(to: NSPoint(x: 102, y: 73))
        base.line(to: NSPoint(x: 378, y: 73))
        base.line(to: NSPoint(x: 410, y: 46))
        base.line(to: NSPoint(x: 70, y: 46))
        base.close()
        NSGradient(starting: .lightGray, ending: .gray)?.draw(in: base, angle: 90)
        NSColor(calibratedWhite: 0.38, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 70, y: 42, width: 340, height: 5), xRadius: 3, yRadius: 3).fill()
        NSColor(calibratedWhite: 0.5, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 211, y: 50, width: 58, height: 12), xRadius: 3, yRadius: 3).fill()
    }
}
