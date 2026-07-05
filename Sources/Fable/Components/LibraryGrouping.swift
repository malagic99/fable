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
        L10n.string("grouping.\(rawValue)")
    }
}

/// One titled slice of the game wall under a grouping — pure data, so the
/// slicing logic is testable without a view in sight.
struct LibrarySection: Identifiable {
    let id: String
    let title: String?
    var wine: [LibraryEntry] = []
    var native: [NativeGame] = []
}

extension LibraryGrouping {
    /// Slices the wall. `.none` = one untitled section. Native games always
    /// form their own section under health/bottle grouping (they have no
    /// verdict and no bottle).
    func sections(
        entries: [LibraryEntry],
        natives: [NativeGame],
        bottles: [Bottle],
        confidence: (LibraryEntry) -> GameConfidence
    ) -> [LibrarySection] {
        switch self {
        case .none:
            return [LibrarySection(id: "all", title: nil, wine: entries, native: natives)]
        case .platform:
            return [
                LibrarySection(id: "wine", title: L10n.string("wall.section.windows"), wine: entries),
                LibrarySection(id: "native", title: L10n.string("wall.section.native"), native: natives),
            ].filter { !$0.wine.isEmpty || !$0.native.isEmpty }
        case .health:
            var byVerdict: [GameConfidence: [LibraryEntry]] = [:]
            for entry in entries { byVerdict[confidence(entry), default: []].append(entry) }
            var result: [LibrarySection] = GameConfidence.allCases.compactMap { verdict in
                guard let games = byVerdict[verdict], !games.isEmpty else { return nil }
                return LibrarySection(id: verdict.label, title: verdict.label.capitalized, wine: games)
            }
            if !natives.isEmpty {
                result.append(LibrarySection(id: "native", title: L10n.string("wall.section.native"), native: natives))
            }
            return result
        case .bottle:
            // Bottle doubles as the account boundary (two Steam accounts =
            // two bottles), so this is also the "by account" view.
            var result: [LibrarySection] = bottles.compactMap { bottle in
                let games = entries.filter { $0.bottle.id == bottle.id }
                guard !games.isEmpty else { return nil }
                return LibrarySection(id: bottle.id.uuidString, title: bottle.name, wine: games)
            }
            if !natives.isEmpty {
                result.append(LibrarySection(id: "native", title: L10n.string("wall.section.native"), native: natives))
            }
            return result
        }
    }
}
