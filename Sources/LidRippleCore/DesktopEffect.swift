/// Presentation choice; both effects share the same sensor and privacy lifecycle.
public enum DesktopEffect: String, CaseIterable, Sendable {
    case fold
    case ripple

    public var title: String { self == .fold ? "Fold" : "Ripple" }
}
