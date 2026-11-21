import Foundation
import Testing
@testable import Fable

/// The cover wall's confidence verdict + the interface-style setting.
@Suite struct GameConfidenceTests {
    /// The rules through the one function the app uses. `hasRecipe` stands
    /// for a recipe whose backend isn't known to differ from the game's.
    private func assess(
        hasRecipe: Bool, findings: [CompatibilityFinding], stats: GameStatsStore.Stats? = nil
    ) -> GameConfidence {
        let recipe = GameRecipe(
            name: "R", executables: ["r.exe"], backend: .sikarugir, metalFX: false, frameRateCap: nil, note: "")
        return GameConfidence.assessment(
            recipe: hasRecipe ? recipe : nil, backend: nil, findings: findings, stats: stats).confidence
    }


    private func finding(_ severity: CompatibilityFinding.Severity) -> CompatibilityFinding {
        CompatibilityFinding(id: "t", severity: severity, title: "t", detail: "d", suggestion: "s")
    }

    @Test
    func blockerAlwaysWins() {
        // Even a verified recipe can't outrank a kernel anti-cheat blocker.
        #expect(assess(hasRecipe: true, findings: [finding(.knownBlocker)]) == .blocked)
        #expect(assess(hasRecipe: false, findings: [finding(.knownBlocker), finding(.caveat)]) == .blocked)
    }

    @Test
    func caveatBeatsRecipe() {
        #expect(assess(hasRecipe: true, findings: [finding(.caveat)]) == .caveat)
    }

    @Test
    func recipeEarnsVerified() {
        #expect(assess(hasRecipe: true, findings: []) == .verified)
        #expect(assess(hasRecipe: true, findings: [finding(.info)]) == .verified)
    }

    @Test
    func noSignalIsHonestlyUnknown() {
        #expect(assess(hasRecipe: false, findings: []) == .unknown)
        #expect(assess(hasRecipe: false, findings: [finding(.info)]) == .unknown)
    }

    @Test
    func realSessionsEarnPlayedButNeverVerified() {
        var stats = GameStatsStore.Stats()
        stats.totalSeconds = 3600

        // An hour of tracked play, no crashes → "played on this Mac".
        #expect(assess(hasRecipe: false, findings: [], stats: stats) == .played)
        // A recipe still outranks observation (a recipe says HOW it works;
        // playtime only says THAT it ran — see Absolute Drift's white screen).
        #expect(assess(hasRecipe: true, findings: [], stats: stats) == .verified)
        // Findings outrank observation too.
        #expect(assess(hasRecipe: false, findings: [finding(.knownBlocker)], stats: stats) == .blocked)

        // A few launch attempts aren't evidence.
        stats.totalSeconds = 120
        #expect(assess(hasRecipe: false, findings: [], stats: stats) == .unknown)

        // Crash signatures poison the claim — it ran, but not cleanly.
        stats.totalSeconds = 7200
        stats.crashSignatures = ["sikarugir": "int3"]
        #expect(assess(hasRecipe: false, findings: [], stats: stats) == .unknown)

        // No stats at all (the pre-tracking world) stays unknown.
        #expect(assess(hasRecipe: false, findings: [], stats: nil) == .unknown)
    }
}

/// Interface style: persistence default + round-trip.
@Suite struct InterfaceStyleTests {

    @Test
    func configsWithoutTheFieldDecodeToClassic() throws {
        // An existing user's config predates the field — no surprise change.
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(decoded.interfaceStyle == .classic)
    }

    @Test
    func gamerChoiceSurvivesARoundTrip() throws {
        var settings = AppSettings()
        settings.interfaceStyle = .gamer
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.interfaceStyle == .gamer)
    }
}

/// Tile sizing clamp — a stored scale never escapes the usable range.
@Suite struct TileMetricsTests {
    @Test
    func scaleClampsToRange() {
        #expect(TileMetrics.clamp(0.1) == TileMetrics.range.lowerBound)
        #expect(TileMetrics.clamp(9.0) == TileMetrics.range.upperBound)
        #expect(TileMetrics.clamp(1.0) == 1.0)
    }

    @Test
    func biggerScaleMeansBiggerTiles() {
        #expect(TileMetrics.coverMin(1.5) > TileMetrics.coverMin(1.0))
        #expect(TileMetrics.cardMin(1.5) > TileMetrics.cardMin(1.0))
    }

    @Test
    func anOutOfRangeStoredScaleDecodesClamped() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"tileScale": 99}"#.utf8))
        #expect(decoded.tileScale == TileMetrics.range.upperBound)
    }
}
