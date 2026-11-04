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
    func anExeDerivedNameMatchesWhenOnlySpacingDiffers() {
        // Real store search for "Stalker2" (GOG install named after its exe),
        // 2026-11-04. The dots in S.T.A.L.K.E.R. normalize to spaces.
        let json = """
        {"total":3,"items":[
            {"id":1643320,"name":"S.T.A.L.K.E.R. 2: Heart of Chornobyl"},
            {"id":3765020,"name":"S.T.A.L.K.E.R. 2: Cost of Hope"},
            {"id":1661620,"name":"S.T.A.L.K.E.R. 2: Heart of Chornobyl - Deluxe Upgrade"}
        ]}
        """
        #expect(GameArtwork.appID(fromStoreSearch: Data(json.utf8), matching: "Stalker2") == 1643320)
        // Spacing-only rule still refuses unrelated titles.
        #expect(GameArtwork.appID(fromStoreSearch: Data(json.utf8), matching: "Stalker 3") == nil)
        #expect(GameArtwork.appID(fromStoreSearch: Data(json.utf8), matching: "...") == nil)
    }

    @Test
    func newerTitlesCoverComesFromTheStoreAssetPath() throws {
        // Real IStoreBrowseService/GetItems reply for The Jackbox Party Pack 12
        // (4199960), trimmed — its old CDN path 404s.
        let json = """
        {"response":{"store_items":[{"appid":4199960,"assets":{
            "asset_url_format":"steam/apps/4199960/${FILENAME}?t=1792701225",
            "library_capsule":"27756779b27acac96dcdbddf1d1587e6125b0937/library_capsule.jpg",
            "library_capsule_2x":"27756779b27acac96dcdbddf1d1587e6125b0937/library_capsule_2x.jpg"}}]}}
        """
        #expect(GameArtwork.coverURL(fromStoreItems: Data(json.utf8))?.absoluteString
                == "https://shared.steamstatic.com/store_item_assets/steam/apps/4199960/27756779b27acac96dcdbddf1d1587e6125b0937/library_capsule_2x.jpg?t=1792701225")

        // 1x when that's all there is; nothing without a capsule or format.
        let oneX = #"{"response":{"store_items":[{"appid":7,"assets":{"asset_url_format":"steam/apps/7/${FILENAME}","library_capsule":"abc/library_capsule.jpg"}}]}}"#
        #expect(GameArtwork.coverURL(fromStoreItems: Data(oneX.utf8))?.lastPathComponent == "library_capsule.jpg")
        #expect(GameArtwork.coverURL(fromStoreItems: Data(#"{"response":{"store_items":[{"appid":1}]}}"#.utf8)) == nil)
        #expect(GameArtwork.coverURL(fromStoreItems: Data("junk".utf8)) == nil)

        let lookup = GameArtwork.storeItemsURL(appID: 4199960)
        #expect(lookup.host == "api.steampowered.com")
        #expect(lookup.query(percentEncoded: false)?.contains(#""appid":4199960"#) == true)
        #expect(lookup.query(percentEncoded: false)?.contains(#""include_assets":true"#) == true)
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
