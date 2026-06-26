import Foundation
import Testing
@testable import Fable

/// Flattening, sorting, and search for the cross-bottle Library.
@MainActor
@Suite struct LibraryIndexTests {

    private func bottle(_ name: String, backend: GraphicsBackend = .off, games: [Game]) -> Bottle {
        var b = Bottle(name: name, graphicsBackend: backend)
        b.games = games
        return b
    }

    @Test
    func flattensGamesAcrossBottlesSortedByName() {
        let bottles = [
            bottle("Steam", games: [Game(name: "Witcher 3", executablePath: "w3.exe"),
                                    Game(name: "Balatro", executablePath: "balatro.exe")]),
            bottle("Classic", games: [Game(name: "Arx Fatalis", executablePath: "arx.exe")]),
        ]
        let names = LibraryIndex.entries(from: bottles).map(\.game.name)
        #expect(names == ["Arx Fatalis", "Balatro", "Witcher 3"])
    }

    @Test
    func searchMatchesGameOrBottleName() {
        let bottles = [
            bottle("Steam", games: [Game(name: "Balatro", executablePath: "balatro.exe")]),
            bottle("Retro Pack", games: [Game(name: "Doom", executablePath: "doom.exe")]),
        ]
        // Matches on game name.
        #expect(LibraryIndex.entries(from: bottles, query: "bala").map(\.game.name) == ["Balatro"])
        // Matches on bottle name, case-insensitively.
        #expect(LibraryIndex.entries(from: bottles, query: "RETRO").map(\.game.name) == ["Doom"])
        // No match → empty.
        #expect(LibraryIndex.entries(from: bottles, query: "zzz").isEmpty)
        // Blank query → everything.
        #expect(LibraryIndex.entries(from: bottles, query: "   ").count == 2)
    }

    @Test
    func effectiveBackendPrefersPerGameOverride() {
        let b = bottle("Mixed", backend: .sikarugir, games: [
            Game(name: "Inherits", executablePath: "a.exe"),
            Game(name: "Override", executablePath: "b.exe", graphicsBackend: .dxvk),
        ])
        let entries = LibraryIndex.entries(from: [b])
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.game.name, $0.effectiveBackend) })
        #expect(byName["Inherits"] == .sikarugir)   // falls back to the bottle
        #expect(byName["Override"] == .dxvk)         // per-game wins
    }

    @Test
    func entryIdsAreUniqueAcrossBottles() {
        let shared = Game(name: "Same", executablePath: "same.exe")
        let bottles = [
            bottle("One", games: [shared]),
            bottle("Two", games: [shared]),
        ]
        let entries = LibraryIndex.entries(from: bottles)
        #expect(entries.count == 2)
        #expect(Set(entries.map(\.id)).count == 2)   // distinct even with the same game id
    }

    @Test
    func emptyWhenNoGames() {
        #expect(LibraryIndex.entries(from: [bottle("Empty", games: [])]).isEmpty)
        #expect(LibraryIndex.entries(from: []).isEmpty)
    }
}
