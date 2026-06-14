import Foundation
import SwiftUI

/// One thing the compatibility scanner noticed about a game install
/// that the user should know about *before* spending an hour debugging
/// a crash. Forms the foundation of Smart Bottle — same Finding shape
/// will later feed the log-pattern matcher (Tier 3 Day 54).
struct CompatibilityFinding: Hashable, Sendable, Identifiable {
    enum Severity: String, Codable, Hashable, Sendable {
        /// Worth knowing about but not a real obstacle.
        case info
        /// Likely to need tweaking — community has workarounds.
        case caveat
        /// Known not to work on macOS/Wine today, regardless of config.
        case knownBlocker

        var systemImage: String {
            switch self {
            case .info: "info.circle"
            case .caveat: "exclamationmark.triangle"
            case .knownBlocker: "xmark.octagon"
            }
        }

        var tint: Color {
            switch self {
            case .info: .secondary
            case .caveat: .yellow
            case .knownBlocker: .red
            }
        }
    }

    let id: String
    let severity: Severity
    /// One-line summary, shown in the collapsed banner.
    let title: String
    /// Longer explanation, shown when expanded.
    let detail: String
    /// Actionable next step the user can take. Empty when there isn't
    /// one — e.g. a knownBlocker with no workaround.
    let suggestion: String
}
