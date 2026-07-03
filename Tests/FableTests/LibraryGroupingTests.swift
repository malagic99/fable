import Foundation
import Testing
@testable import Fable

/// The wall's grouping logic — pure slices, no view involved.
@Suite struct LibraryGroupingTests {
    private let bottleA = Bottle(name: "Steam Main")
    private let bottleB = Bottle(name: "Steam Alt")

    private var entries: [LibraryEntry] {
        [
            LibraryEntry(game: Game(name: "Verified One", executablePath: "v.exe"), bottle: bottleA),
            LibraryEntry(game: Game(name: "Mystery", executablePath: "m.exe"), bottle: bottleA),
            LibraryEntry(game: Game(name: "Alt Game", executablePath: "a.exe"), bottle: bottleB),
        ]
    }

    private var natives: [NativeGame] {
        [NativeGame(name: "Balatro", source: .steam(appID: 1))]
    }

    /// v.exe is verified, everything else untested.
    private func confidence(_ entry: LibraryEntry) -> GameConfidence {
        entry.game.executablePath == "v.exe" ? .verified : .unknown
    }

    @Test
    func noGroupingIsOneUntitledSection() {
        let sections = LibraryGrouping.none.sections(
            entries: entries, natives: natives, bottles: [bottleA, bottleB], confidence: confidence
        )
        #expect(sections.count == 1)
        #expect(sections[0].title == nil)
        #expect(sections[0].wine.count == 3)
        #expect(sections[0].native.count == 1)
    }

    @Test
    func platformSplitsWineFromNative() {
        let sections = LibraryGrouping.platform.sections(
            entries: entries, natives: natives, bottles: [bottleA, bottleB], confidence: confidence
        )
        #expect(sections.map(\.title) == ["Windows", "Native Mac"])
        #expect(sections[0].native.isEmpty)
        #expect(sections[1].wine.isEmpty)

        // Empty sides drop out entirely.
        let wineOnly = LibraryGrouping.platform.sections(
            entries: entries, natives: [], bottles: [bottleA], confidence: confidence
        )
        #expect(wineOnly.map(\.title) == ["Windows"])
    }

    @Test
    func healthBucketsByVerdictAndNativesGetTheirOwnSection() {
        let sections = LibraryGrouping.health.sections(
            entries: entries, natives: natives, bottles: [bottleA, bottleB], confidence: confidence
        )
        // verified first (enum order), then untested, then natives; empty
        // verdicts (caveat/blocked) never appear.
        #expect(sections.map(\.title) == ["Verified", "Untested", "Native Mac"])
        #expect(sections[0].wine.map(\.game.name) == ["Verified One"])
        #expect(sections[1].wine.count == 2)
    }

    @Test
    func bottleGroupingIsTheAccountView() {
        let sections = LibraryGrouping.bottle.sections(
            entries: entries, natives: natives, bottles: [bottleA, bottleB], confidence: confidence
        )
        #expect(sections.map(\.title) == ["Steam Main", "Steam Alt", "Native Mac"])
        #expect(sections[0].wine.count == 2)
        #expect(sections[1].wine.map(\.game.name) == ["Alt Game"])

        // A bottle with no games doesn't produce an empty header.
        let emptyBottle = Bottle(name: "Empty")
        let withEmpty = LibraryGrouping.bottle.sections(
            entries: entries, natives: [], bottles: [bottleA, bottleB, emptyBottle], confidence: confidence
        )
        #expect(!withEmpty.contains { $0.title == "Empty" })
    }
}
