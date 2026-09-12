import Foundation

public enum FoldPhase: String, Codable, Sendable, CaseIterable {
    /// Lid open and static. Nothing captured, nothing drawn.
    case idle
    /// Closing intent detected. Capture warms; still nothing drawn.
    case armed
    /// The fold is running forward.
    case folding
    /// The fold is running backward, tracking the lid.
    case unfolding
    /// Fully folded. Holds the final frame until teardown.
    case sealed
}

public struct FoldState: Equatable, Sendable {
    public let phase: FoldPhase
    /// 0 is fully unfolded, 1 is fully folded. May slightly exceed 1 up to
    /// `FoldTuning.maxProgress`; the renderer reads the excess as extra void.
    public let progress: Double
    /// Rate of change of `progress`, per second.
    public let velocity: Double

    public init(phase: FoldPhase, progress: Double, velocity: Double) {
        self.phase = phase
        self.progress = progress
        self.velocity = velocity
    }

    public static let idle = FoldState(phase: .idle, progress: 0, velocity: 0)
}
