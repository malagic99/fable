import Foundation
import Testing
@testable import Fable

/// The cover-art pipeline's pure parts: URL building, response parsing with
/// name-match safety, cache keys, and the Steam-client exclusion.
@Suite struct GameArtworkTests {

    @Test
    func steamCDNURLTargetsThePortraitCapsule() {
        let url = GameArtwork.steamCoverURL(appID: 1252330)
        #expect(url.absoluteString == "https://cdn.cloudflare.steamstatic.com/steam/apps/1252330/library_600x900.jpg")
    }

    @Test
    func storeSearchMatchesNormalizedNamesOnly() {
        let json = """
        {"total":3,"items":[
            {"id":111,"name":"Some Other Game"},
            {"id":222,"name":"System Shock® 2"},
            {"id":333,"name":"System Shock 2: Deluxe"}
        ]}
        """
        // ™/® and punctuation don't block the exact match.
        #expect(GameArtwork.appID(fromStoreSearch: Data(json.utf8), matching: "System Shock 2") == 222)
    }

    @Test
    func storeSearchRejectsUnrelatedResults() {
        let json = #"{"total":1,"items":[{"id":999,"name":"Completely Different Title"}]}"#
        // A result that shares no prefix with the query must NOT be used —
        // wrong art is worse than no art.
        #expect(GameArtwork.appID(fromStoreSearch: Data(json.utf8), matching: "Absolute Drift") == nil)
    }

    @Test
    func sgdbResponsesParse() {
        let search = #"{"success":true,"data":[{"id":5001,"name":"Ready or Not"}]}"#
        #expect(GameArtwork.gameID(fromSGDBSearch: Data(search.utf8)) == 5001)

        let grids = #"{"success":true,"data":[{"id":1,"url":"https://cdn2.steamgriddb.com/grid/abc.png"}]}"#
        #expect(GameArtwork.gridURL(fromSGDBGrids: Data(grids.utf8))?.absoluteString
                == "https://cdn2.steamgriddb.com/grid/abc.png")
    }

    @Test
    func cacheKeysAreStableAndFilenameSafe() {
        #expect(GameArtwork.cacheKey(for: "System Shock® 2") == "system-shock-2")
        #expect(GameArtwork.cacheKey(for: "READY OR NOT") == GameArtwork.cacheKey(for: "Ready or Not"))
        #expect(!GameArtwork.cacheKey(for: "A/B: C").contains("/"))
    }

    @Test
    func theSteamClientItselfIsExcluded() {
        let steam = Game(name: "Steam", executablePath: "Program Files (x86)/Steam/steam.exe")
        let game = Game(name: "DEATHLOOP", executablePath: "steamapps/common/DEATHLOOP/DEATHLOOP.exe")
        #expect(GameArtwork.isSteamClient(steam))
        #expect(!GameArtwork.isSteamClient(game))
    }

    @Test
    func malformedResponsesAreNil() {
        #expect(GameArtwork.appID(fromStoreSearch: Data("junk".utf8), matching: "X") == nil)
        #expect(GameArtwork.gameID(fromSGDBSearch: Data("junk".utf8)) == nil)
        #expect(GameArtwork.gridURL(fromSGDBGrids: Data("{}".utf8)) == nil)
    }
}
