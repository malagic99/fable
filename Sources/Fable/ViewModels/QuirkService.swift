import Foundation

/// The quirk system's coordinator: loads external per-game compatibility
/// sources once and answers preemptive findings for the compatibility banner,
/// so known problems surface *before* you install and troubleshoot.
///
/// Slice 1 is the offline `AntiCheatDatabase` (no network, no consent needed).
/// ProtonDB (online, opt-in, cached) plugs in here next behind the same
/// `findings(forGameNamed:)` surface.
@MainActor
final class QuirkService: ObservableObject {
    /// Flips true once sources finish loading (lets the UI re-query if needed).
    @Published private(set) var isReady = false

    private var antiCheat: AntiCheatDatabase?

    init() {
        Task { await loadSources() }
    }

    /// Direct-injection initializer for tests and previews.
    init(antiCheat: AntiCheatDatabase?) {
        self.antiCheat = antiCheat
        isReady = true
    }

    private func loadSources() async {
        let db = await Task.detached(priority: .utility) {
            AntiCheatDatabase.loadFromDefaultLocations()
        }.value
        antiCheat = db
        isReady = true
    }

    /// Preemptive compatibility findings for a game by name. Empty when nothing
    /// is known — pure data the banner merges with its filesystem scan.
    func findings(forGameNamed name: String) -> [CompatibilityFinding] {
        guard let finding = antiCheat?.finding(forGameNamed: name) else { return [] }
        return [finding]
    }
}
