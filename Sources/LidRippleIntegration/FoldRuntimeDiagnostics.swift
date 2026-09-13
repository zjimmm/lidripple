import LidRippleCore

/// Pixel-free state exposed for tests and M5's menu bar. It deliberately says
/// whether resources exist without retaining or exposing captured content.
public struct FoldRuntimeDiagnostics: Equatable, Sendable {
    public let state: FoldState
    public let availability: FoldLifecycleAvailability
    public let hasInstalledFrame: Bool
    public let requiresScriptedUnfold: Bool
    public let usesFallbackReveal: Bool
    public let reducedQuality: Bool
    public let captureActivity: FoldCaptureActivity
    public let overlayVisible: Bool
    public let inputAvailability: FoldInputAvailability
    public let builtInDisplayAvailable: Bool
    public let sessionRestricted: Bool
    public let lastCaptureErrorDescription: String?

    public init(
        state: FoldState,
        availability: FoldLifecycleAvailability,
        hasInstalledFrame: Bool,
        requiresScriptedUnfold: Bool,
        usesFallbackReveal: Bool,
        reducedQuality: Bool,
        captureActivity: FoldCaptureActivity,
        overlayVisible: Bool,
        inputAvailability: FoldInputAvailability,
        builtInDisplayAvailable: Bool,
        sessionRestricted: Bool,
        lastCaptureErrorDescription: String?
    ) {
        self.state = state
        self.availability = availability
        self.hasInstalledFrame = hasInstalledFrame
        self.requiresScriptedUnfold = requiresScriptedUnfold
        self.usesFallbackReveal = usesFallbackReveal
        self.reducedQuality = reducedQuality
        self.captureActivity = captureActivity
        self.overlayVisible = overlayVisible
        self.inputAvailability = inputAvailability
        self.builtInDisplayAvailable = builtInDisplayAvailable
        self.sessionRestricted = sessionRestricted
        self.lastCaptureErrorDescription = lastCaptureErrorDescription
    }
}

public enum FoldCaptureActivity: Equatable, Sendable {
    case idle
    case warming
    case freezing
    case frozen
}

public enum FoldInputAvailability: Equatable, Sendable {
    case sensor
    case timedFallback
    case unavailable
}
