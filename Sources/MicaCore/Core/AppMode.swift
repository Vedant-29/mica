import Foundation

/// The tri-state the menu bar control drives.
public nonisolated enum AppMode: String, CaseIterable, Codable, Sendable {
    /// Force every enabled effect on and keep it on, regardless of triggers.
    case on
    /// Engage when a trigger fires, release when it clears.
    case auto
    /// Fully disengaged; triggers are not evaluated.
    case off

    public var displayName: String {
        switch self {
        case .on: "On"
        case .auto: "Auto"
        case .off: "Off"
        }
    }
}
