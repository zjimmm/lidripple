import AppKit
import CoreGraphics
import Foundation
@preconcurrency import MetalKit
import QuartzCore
import LidRippleCapture
import LidRippleCore

/// Type-erased presentation surface used by `OverlayPresenter` and its tests.
/// The production implementation is `FoldMetalView`; fakes need no Metal device
/// or WindowServer drawable.
@MainActor
public protocol FoldPresentation: AnyObject {
    var view: NSView { get }
    func setSource(_ frame: CapturedFrame) throws
    func clearSource()
    func update(_ state: FoldState)
}

/// Native-scale, vsynced presentation adapter for `FoldRenderer`.
/// `MTKView` is backed by a `CAMetalLayer`; three drawable slots match the
/// renderer's three in-flight uniform buffers.
@MainActor
public final class FoldMetalView: MTKView, MTKViewDelegate, FoldPresentation {
    public var view: NSView { self }
    public private(set) var progress: Double = 0
    public private(set) var lastRenderError: Error?

    private let foldRenderer: FoldRenderer
    private let commandQueue: any MTLCommandQueue
    private var hasSource = false
    private var phase: FoldPhase = .idle

    public convenience init(
        frame: NSRect,
        tuning: FoldTuning = .default
    ) throws {
        let renderer = try FoldRenderer(tuning: tuning)
        try self.init(frame: frame, renderer: renderer)
    }

    init(frame: NSRect, renderer: FoldRenderer) throws {
        foldRenderer = renderer
        guard let commandQueue = renderer.device.makeCommandQueue() else {
            throw RendererError.commandQueueCreationFailed
        }
        self.commandQueue = commandQueue
        super.init(frame: frame, device: renderer.device)

        colorPixelFormat = .bgra8Unorm
        depthStencilPixelFormat = .invalid
        sampleCount = 1
        framebufferOnly = true
        presentsWithTransaction = false
        enableSetNeedsDisplay = true
        isPaused = true
        preferredFramesPerSecond = 60
        autoResizeDrawable = false
        clearColor = MTLClearColor(
            red: renderer.tuning.warmBlackRed,
            green: renderer.tuning.warmBlackGreen,
            blue: renderer.tuning.warmBlackBlue,
            alpha: 1
        )
        delegate = self

        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.displaySyncEnabled = true
            metalLayer.maximumDrawableCount = 3
        }
        synchronizeDrawableSize()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("FoldMetalView must be created programmatically")
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        synchronizeDrawableSize()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        synchronizeDrawableSize()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        synchronizeDrawableSize()
    }

    public func setSource(_ frame: CapturedFrame) throws {
        try foldRenderer.setSource(frame)
        didInstallSource()
    }

    /// Installs deterministic content for preview and renderer UI tests without
    /// constructing a ScreenCaptureKit frame or requesting TCC permission.
    public func setPreviewSource(_ texture: any MTLTexture) throws {
        try foldRenderer.setSource(texture: texture)
        didInstallSource()
    }

    public func clearSource() {
        foldRenderer.clearSource()
        hasSource = false
        isPaused = true
    }

    public func update(_ state: FoldState) {
        phase = state.phase
        progress = state.progress
        updateDrawingState()
    }

    public func draw(in view: MTKView) {
        guard hasSource, let drawable = currentDrawable else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            lastRenderError = RendererError.commandBufferCreationFailed
            return
        }

        do {
            guard try foldRenderer.render(
                progress: progress,
                to: drawable.texture,
                commandBuffer: commandBuffer
            ) else { return }
            commandBuffer.present(drawable)
            commandBuffer.commit()
        } catch {
            lastRenderError = error
        }
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    static func pixelSize(points: CGSize, backingScale: CGFloat) -> CGSize {
        CGSize(
            width: max((points.width * backingScale).rounded(), 1),
            height: max((points.height * backingScale).rounded(), 1)
        )
    }

    private func didInstallSource() {
        hasSource = true
        lastRenderError = nil
        updateDrawingState()
    }

    private func updateDrawingState() {
        switch phase {
        case .idle, .armed:
            isPaused = true
        case .folding, .unfolding, .sealed:
            isPaused = !hasSource
            if hasSource { draw() }
        }
    }

    private func synchronizeDrawableSize() {
        let scale = window?.backingScaleFactor
            ?? window?.screen?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 1
        drawableSize = Self.pixelSize(points: bounds.size, backingScale: scale)
    }
}
