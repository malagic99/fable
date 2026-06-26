import Foundation
import Testing
@testable import Fable

/// ProtonDB tier mapping, summary decoding, cache, appid resolution, and the
/// QuirkService lookup — all offline; the network is a stub.
@Suite struct ProtonDBTests {
    private let fm = FileManager.default

    @Test
    func tiersMapToSeverity() {
        #expect(ProtonDB.severity(forTier: "platinum") == .info)
        #expect(ProtonDB.severity(forTier: "gold") == .info)
        #expect(ProtonDB.severity(forTier: "silver") == .caveat)
        #expect(ProtonDB.severity(forTier: "borked") == .caveat)   // signal, never a hard block
        #expect(ProtonDB.severity(forTier: "pending") == nil)
    }

    @Test
    func decodesRealShapedSummaryAndBuildsAFinding() throws {
        let json = """
        {"bestReportedTier":"platinum","confidence":"strong","score":0.88,"tier":"gold","total":260,"trendingTier":"gold"}
        """
        let summary = try JSONDecoder().decode(ProtonDBSummary.self, from: Data(json.utf8))
        #expect(summary.tier == "gold")
        #expect(summary.total == 260)
        let finding = ProtonDB.finding(from: summary, appID: 12345)
        #expect(finding?.severity == .info)
        #expect(finding?.title.contains("260") == true)
        #expect(finding?.id == "protondb")
    }

    @Test
    func cacheStoresAndRespectsTTL() {
        let dir = fm.temporaryDirectory.appending(path: "pdb-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: dir) }
        let cache = ProtonDBCache(directory: dir)
        let summary = ProtonDBSummary(tier: "gold", confidence: "strong", score: 0.8, total: 100,
                                      trendingTier: "gold", bestReportedTier: "platinum")
        let now = Date()
        cache.store(summary, appID: 42, now: now)

        // Fresh → returned.
        #expect(cache.cached(appID: 42, now: now.addingTimeInterval(60)) == summary)
        // Past the TTL → ignored.
        #expect(cache.cached(appID: 42, maxAge: 3600, now: now.addingTimeInterval(7200)) == nil)
        // Unknown appid → nil.
        #expect(cache.cached(appID: 999, now: now) == nil)
    }

    // MARK: appid resolution

    @Test
    func installDirParsedFromSteamExePath() {
        let path = "Program Files (x86)/Steam/steamapps/common/DEATHLOOP/DEATHLOOP.exe"
        #expect(SteamAppManifest.installDir(fromExecutablePath: path) == "DEATHLOOP")
        // Non-Steam path → nil.
        #expect(SteamAppManifest.installDir(fromExecutablePath: "Games/Foo/foo.exe") == nil)
    }

    @Test
    func appIDResolvedFromAppManifest() throws {
        let root = fm.temporaryDirectory.appending(path: "steam-\(UUID().uuidString)", directoryHint: .isDirectory)
        let steamapps = root.appending(path: "steamapps", directoryHint: .isDirectory)
        try fm.createDirectory(at: steamapps, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let acf = """
        "AppState"
        {
        	"appid"		"1252330"
        	"installdir"		"DEATHLOOP"
        }
        """
        try acf.write(to: steamapps.appending(path: "appmanifest_1252330.acf"), atomically: true, encoding: .utf8)

        #expect(SteamAppManifest.appID(forInstallDir: "DEATHLOOP", steamRoot: root) == 1252330)
        #expect(SteamAppManifest.appID(forInstallDir: "Nope", steamRoot: root) == nil)
    }

    // MARK: QuirkService lookup

    private struct StubClient: ProtonDBFetching {
        let summary: ProtonDBSummary?
        var calls = Counter()
        func summary(appID: Int) async -> ProtonDBSummary? { calls.bump(); return summary }
        final class Counter: @unchecked Sendable { private(set) var n = 0; func bump() { n += 1 } }
    }

    @MainActor
    @Test
    func quirkServiceFetchesOnceThenServesFromCache() async {
        let dir = fm.temporaryDirectory.appending(path: "pdb-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: dir) }
        let stub = StubClient(summary: ProtonDBSummary(tier: "platinum", confidence: nil, score: nil,
                                                       total: 10, trendingTier: nil, bestReportedTier: nil))
        let service = QuirkService(antiCheat: nil, protonDB: stub, protonCache: ProtonDBCache(directory: dir))

        let first = await service.protonDBFinding(appID: 7)
        #expect(first?.severity == .info)
        let second = await service.protonDBFinding(appID: 7)   // should hit the cache
        #expect(second?.severity == .info)
        #expect(stub.calls.n == 1)   // network touched exactly once
    }
}
