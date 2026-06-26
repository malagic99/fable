import Foundation

/// One game in the cross-bottle Library: the game plus the bottle it lives in.
struct LibraryEntry: Identifiable, Hashable, Sendable {
    let game: Game
    let bottle: Bottle

    /// Stable across bottles — a game id is unique, but pair with the bottle
    /// so the same exe imported into two bottles stays distinct.
    var id: String { "\(bottle.id.uuidString):\(game.id.uuidString)" }

    /// The backend this game actually launches on (its override, else the
    /// bottle's) — for the chip in the Library row.
    var effectiveBackend: GraphicsBackend { game.graphicsBackend ?? bottle.graphicsBackend }
}

/// Flattens every game across every bottle into one searchable, sorted list —
/// the data behind the Library view. Pure, so it's trivially testable.
enum LibraryIndex {
    /// Every game across `bottles`, sorted by game name (case-insensitive,
    /// bottle name as tiebreak), optionally filtered by a query that matches
    /// the game *or* bottle name.
    static func entries(from bottles: [Bottle], query: String = "") -> [LibraryEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var entries: [LibraryEntry] = []
        for bottle in bottles {
            for game in bottle.games {
                guard needle.isEmpty
                    || game.name.lowercased().contains(needle)
                    || bottle.name.lowercased().contains(needle)
                else { continue }
                entries.append(LibraryEntry(game: game, bottle: bottle))
            }
        }
        return entries.sorted {
            let lhs = $0.game.name.localizedCaseInsensitiveCompare($1.game.name)
            if lhs != .orderedSame { return lhs == .orderedAscending }
            return $0.bottle.name.localizedCaseInsensitiveCompare($1.bottle.name) == .orderedAscending
        }
    }
}
