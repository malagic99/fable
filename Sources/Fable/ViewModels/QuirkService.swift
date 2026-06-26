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
    private let protonDB: ProtonDBFetching
    private let protonCache: ProtonDBCache

    init(protonDB: ProtonDBFetching = ProtonDBClient(), protonCache: ProtonDBCache = ProtonDBCache()) {
        self.protonDB = protonDB
        self.protonCache = protonCache
        Task { await loadSources() }
    }

    /// Direct-injection initializer for tests and previews.
    init(
        antiCheat: AntiCheatDatabase?,
        protonDB: ProtonDBFetching = ProtonDBClient(),
        protonCache: ProtonDBCache = ProtonDBCache()
    ) {
        self.antiCheat = antiCheat
        self.protonDB = protonDB
        self.protonCache = protonCache
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

    /// The ProtonDB finding for a Steam appid — cache-first, fetching only on a
    /// miss. The caller (the banner) must already have confirmed the user opted
    /// into online lookups; this method never gates on the setting itself, so
    /// the network is reached only through that one guarded call site.
    func protonDBFinding(appID: Int) async -> CompatibilityFinding? {
        if let cached = protonCache.cached(appID: appID) {
            return ProtonDB.finding(from: cached, appID: appID)
        }
        guard let summary = await protonDB.summary(appID: appID) else { return nil }
        protonCache.store(summary, appID: appID)
        return ProtonDB.finding(from: summary, appID: appID)
    }
}
