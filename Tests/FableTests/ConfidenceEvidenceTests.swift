import Foundation
import Testing
@testable import Fable

/// v1.2 honesty rules: a label says only what its evidence supports, and the
/// evidence is about the engine the game runs on now.
@Suite("Confidence evidence")
struct ConfidenceEvidenceTests {

    private let aceCombat = GameRecipe(
        name: "Ace Combat 8", executables: ["ace8.exe"], backend: .sikarugir11,
        metalFX: false, frameRateCap: nil, note: "")

    private func stats(total: Double, byEngine: [String: Double]? = nil,
                       crashes: [String: String]? = nil) -> GameStatsStore.Stats {
        var stats = GameStatsStore.Stats()
        stats.totalSeconds = total
        stats.secondsByEngine = byEngine
        stats.crashSignatures = crashes
        return stats
    }

    // MARK: Recipes

    @Test
    func aRecipeIsVerifiedOnlyOnTheBackendItWasTestedOn() {
        let matching = GameConfidence.assessment(recipe: aceCombat, backend: .sikarugir11, findings: [])
        #expect(matching.confidence == .verified)
        #expect(matching.evidence == .recipe(name: "Ace Combat 8", backend: .sikarugir11))

        // The false green this replaces: a Wine 10 bottle showed "Verified"
        // for a game that crashes there.
        let other = GameConfidence.assessment(recipe: aceCombat, backend: .sikarugir, findings: [])
        #expect(other.confidence == .caveat)
        #expect(other.evidence == .recipeForOtherBackend(tested: .sikarugir11, current: .sikarugir))
    }

    @Test
    func aRecipeWithNoKnownBackendKeepsTheOldVerdict() {
        // Callers that can't say which backend a game runs on (none today)
        // are not downgraded on a guess.
        #expect(GameConfidence.assessment(recipe: aceCombat, backend: nil, findings: []).confidence == .verified)
    }

    @Test
    func mismatchedRecipeDoesNotFallBackToPlayTime() {
        // Hours of play don't turn an untested backend into a green or blue
        // badge while a tested setup says to use another one.
        let result = GameConfidence.assessment(
            recipe: aceCombat, backend: .sikarugir, findings: [], stats: stats(total: 10 * 3600))
        #expect(result.confidence == .caveat)
    }

    // MARK: Play time per engine

    private let wine10v4 = "sikarugir=WS12WineSikarugir10.0_4"
    private let wine10v8 = "sikarugir=WS12WineSikarugir10.0_8"

    @Test
    func playTimeCountsOnTheEngineInUse() {
        let played = stats(total: 3600, byEngine: [wine10v4: 3600])
        let same = GameConfidence.assessment(
            recipe: nil, backend: .sikarugir, findings: [], stats: played, engineKey: wine10v4)
        #expect(same.confidence == .played)
        #expect(same.evidence == .played(seconds: 3600, engine: wine10v4))

        // Moved to a newer engine: an hour on the old one proves nothing here.
        let moved = GameConfidence.assessment(
            recipe: nil, backend: .sikarugir, findings: [], stats: played, engineKey: wine10v8)
        #expect(moved.confidence == .unknown)
        #expect(moved.evidence == .none(secondsHere: 0, secondsElsewhere: 3600, crashed: false))
    }

    @Test
    func unattributedPlayTimeStillCounts() {
        // No engine to attribute to (CrossOver), or stats nobody attributed.
        let legacy = stats(total: 3600)
        #expect(GameConfidence.assessment(
            recipe: nil, backend: .crossover, findings: [], stats: legacy, engineKey: nil).confidence == .played)
        #expect(GameConfidence.assessment(
            recipe: nil, backend: .sikarugir, findings: [], stats: legacy, engineKey: wine10v4).confidence == .played)
    }

    @Test
    func aCrashKeepsPlayedOffAndSaysSo() {
        let crashed = stats(total: 3600, byEngine: [wine10v4: 3600], crashes: ["sikarugir": "int3"])
        let result = GameConfidence.assessment(
            recipe: nil, backend: .sikarugir, findings: [], stats: crashed, engineKey: wine10v4)
        #expect(result.confidence == .unknown)
        #expect(result.evidence == .none(secondsHere: 3600, secondsElsewhere: 0, crashed: true))
    }

    @Test
    func theOldEntryPointAgreesWithTheNewOne() {
        // assess(hasRecipe:) stays for callers with no bottle; same order.
        let played = stats(total: 3600)
        #expect(GameConfidence.assess(hasRecipe: false, findings: [], stats: played)
            == GameConfidence.assessment(recipe: nil, backend: nil, findings: [], stats: played).confidence)
        #expect(GameConfidence.assess(hasRecipe: true, findings: [])
            == GameConfidence.assessment(recipe: aceCombat, backend: nil, findings: []).confidence)
    }

    // MARK: Engine keys

    @Test
    func engineKeyPrefersThePinAndLeavesTheRendererOut() {
        var runtime = BottleRuntime()
        #expect(runtime.engineKey(for: .sikarugir) == nil)

        runtime = runtime.recordingLaunch(
            backend: .sikarugir11,
            versions: ["sikarugir11": "11.0_1", Sikarugir11Manager.templateComponentID: "1.0.27"])
        #expect(runtime.engineKey(for: .sikarugir11) == "sikarugir11=11.0_1")
        // Another backend in the same bottle has its own engine, not this one.
        #expect(runtime.engineKey(for: .sikarugir) == nil)
        #expect(runtime.engineKey(for: .crossover) == nil)

        // Following newest: nothing is pinned, the last launch is the evidence.
        var following = BottleRuntime()
        following.policy = .followNewest
        following = following.recordingLaunch(backend: .dxmt, versions: ["wine": "11.10_1"])
        #expect(following.engineKey(for: .dxmt) == "wine=11.10_1")
    }

    @Test
    func engineKeyReadsAsANameAndVersion() {
        #expect(BottleRuntime.displayName(forEngineKey: "sikarugir=WS12WineSikarugir10.0_4")
            == "Sikarugir (Wine 10) 10.0_4")
        #expect(BottleRuntime.displayName(forEngineKey: "wine=11.10_1") == "Wine 11.10_1")
    }

    // MARK: Stats

    @Test @MainActor
    func sessionsAreFiledUnderTheirEngineAndLegacyTimeIsAttributedOnce() throws {
        let file = FileManager.default.temporaryDirectory
            .appending(path: "fable-stats-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = GameStatsStore(fileURL: file)
        let game = UUID()
        let start = Date(timeIntervalSince1970: 1_000_000)

        // A session from before per-engine tracking.
        store.sessionStarted(game, at: start)
        store.sessionEnded(game, at: start.addingTimeInterval(1200))
        #expect(store.stats[game]?.secondsByEngine == nil)

        store.attributeLegacyPlaytime(engineKeys: [game: wine10v4])
        #expect(store.stats[game]?.secondsByEngine == [wine10v4: 1200])

        // A second pass must not re-file time under a different engine.
        store.attributeLegacyPlaytime(engineKeys: [game: wine10v8])
        #expect(store.stats[game]?.secondsByEngine == [wine10v4: 1200])

        store.sessionStarted(game, at: start)
        store.sessionEnded(game, engineKey: wine10v8, at: start.addingTimeInterval(300))
        #expect(store.stats[game]?.secondsByEngine == [wine10v4: 1200, wine10v8: 300])
        #expect(store.stats[game]?.totalSeconds == 1500)

        // And it survives a reload.
        #expect(GameStatsStore(fileURL: file).stats[game]?.secondsByEngine?[wine10v8] == 300)
    }

    @Test
    func everyEvidenceHasAReadableSentence() {
        let all: [GameConfidence.Evidence] = [
            .recipe(name: "x", backend: .sikarugir),
            .recipeForOtherBackend(tested: .sikarugir11, current: .sikarugir),
            .played(seconds: 7200, engine: nil),
            .played(seconds: 7200, engine: "wine=11.10_1"),
            .none(secondsHere: 0, secondsElsewhere: 7200, crashed: false),
            .none(secondsHere: 120, secondsElsewhere: 0, crashed: false),
            .none(secondsHere: 0, secondsElsewhere: 0, crashed: true),
            .none(secondsHere: 0, secondsElsewhere: 0, crashed: false),
        ]
        for evidence in all {
            // A missing key comes back as the key itself.
            #expect(!evidence.text.hasPrefix("evidence."))
            #expect(!evidence.text.contains("%@"))
        }
    }
}
