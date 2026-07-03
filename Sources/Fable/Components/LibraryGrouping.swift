import Foundation

/// How the game wall is sectioned.
enum LibraryGrouping: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    /// Windows (Wine) vs native macOS.
    case platform
    /// By confidence verdict (verified / tweaks / won't run / untested).
    case health
    /// By bottle — which is also the account boundary when two Steam accounts
    /// live in separate bottles.
    case bottle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "No Groups"
        case .platform: "Platform"
        case .health: "Health"
        case .bottle: "Bottle"
        }
    }
}
