import SwiftUI

/// The at-a-glance verdict a cover carries in the Gamer interface: will this
/// game run? Synthesized from what Fable already knows — the recipe catalogs
/// (a match means someone verified this exact setup) and the quirk system's
/// anti-cheat findings. Honest by construction: no signal → unknown, never a
/// fake green.
enum GameConfidence: Equatable, Hashable, CaseIterable {
    /// A known-good recipe matches this game.
    case verified
    /// Known caveats (e.g. anti-cheat needs configuration).
    case caveat
    /// A known blocker — kernel anti-cheat that won't run under Wine.
    case blocked
    /// Real tracked sessions on THIS Mac, no crash signatures. Claims
    /// exactly what we know — "it ran" — not "it's perfect": a game can
    /// accumulate playtime while rendering wrong (Absolute Drift's white
    /// screen taught that), so this never upgrades to verified on its own.
    case played
    /// No signal either way.
    case unknown

    /// Tracked playtime below this is a launch attempt, not evidence.
    static let playedEvidenceSeconds: Double = 15 * 60

    /// Verdict from the signals. A blocker always wins (an anti-cheat that
    /// won't run trumps a recipe for the game around it); then caveats; then
    /// a recipe match earns verified; then real observed sessions; otherwise
    /// unknown.
    /// The one entry point views should use — recipe lookup + quirk findings
    /// in one place, so the rule can't drift between call sites.
    @MainActor
    static func assess(
        _ game: Game, recipes: UserRecipeStore, quirks: QuirkService, stats: GameStatsStore.Stats? = nil
    ) -> GameConfidence {
        let hasRecipe = recipes.recipe(forExecutablePath: game.executablePath) != nil
            || GameRecipeCatalog.recipe(forExecutablePath: game.executablePath) != nil
        return assess(hasRecipe: hasRecipe, findings: quirks.findings(forGameNamed: game.name), stats: stats)
    }

    static func assess(
        hasRecipe: Bool, findings: [CompatibilityFinding], stats: GameStatsStore.Stats? = nil
    ) -> GameConfidence {
        if findings.contains(where: { $0.severity == .knownBlocker }) { return .blocked }
        if findings.contains(where: { $0.severity == .caveat }) { return .caveat }
        if hasRecipe { return .verified }
        if let stats,
           stats.totalSeconds >= playedEvidenceSeconds,
           (stats.crashSignatures ?? [:]).isEmpty {
            return .played
        }
        return .unknown
    }

    var tint: Color {
        switch self {
        case .verified: .green
        case .caveat: .orange
        case .blocked: .red
        case .played: .blue
        case .unknown: .secondary
        }
    }

    var label: String {
        L10n.string("confidence.\(String(describing: self))")
    }
}
