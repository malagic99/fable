import Foundation
import Testing
@testable import Fable

/// The cover wall's confidence verdict + the interface-style setting.
@Suite struct GameConfidenceTests {

    private func finding(_ severity: CompatibilityFinding.Severity) -> CompatibilityFinding {
        CompatibilityFinding(id: "t", severity: severity, title: "t", detail: "d", suggestion: "s")
    }

    @Test
    func blockerAlwaysWins() {
        // Even a verified recipe can't outrank a kernel anti-cheat blocker.
        #expect(GameConfidence.assess(hasRecipe: true, findings: [finding(.knownBlocker)]) == .blocked)
        #expect(GameConfidence.assess(hasRecipe: false, findings: [finding(.knownBlocker), finding(.caveat)]) == .blocked)
    }

    @Test
    func caveatBeatsRecipe() {
        #expect(GameConfidence.assess(hasRecipe: true, findings: [finding(.caveat)]) == .caveat)
    }

    @Test
    func recipeEarnsVerified() {
        #expect(GameConfidence.assess(hasRecipe: true, findings: []) == .verified)
        #expect(GameConfidence.assess(hasRecipe: true, findings: [finding(.info)]) == .verified)
    }

    @Test
    func noSignalIsHonestlyUnknown() {
        #expect(GameConfidence.assess(hasRecipe: false, findings: []) == .unknown)
        #expect(GameConfidence.assess(hasRecipe: false, findings: [finding(.info)]) == .unknown)
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
