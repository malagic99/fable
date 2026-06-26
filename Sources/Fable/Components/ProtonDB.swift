import Foundation

/// A ProtonDB report summary for a Steam appid — the crowd's verdict on how
/// well a game runs under Proton/Wine. Linux ≠ macOS, but the same translation
/// stack means a "borked" or "platinum" rating is a strong directional signal.
struct ProtonDBSummary: Codable, Sendable, Equatable {
    /// platinum / gold / silver / bronze / borked / pending.
    let tier: String
    let confidence: String?
    let score: Double?
    let total: Int?
    let trendingTier: String?
    let bestReportedTier: String?
}

/// Maps a ProtonDB summary into the compatibility-banner vocabulary.
enum ProtonDB {
    /// Live summary endpoint (unofficial but long-stable). Only ever fetched
    /// after the user opts into online lookups.
    static func summaryURL(appID: Int) -> URL {
        URL(string: "https://www.protondb.com/api/v1/reports/summaries/\(appID).json")!
    }

    /// Tier → finding severity. Positive tiers are reassurance (info), the
    /// weak/broken tiers are caveats — never a hard blocker, since ProtonDB is
    /// a Linux signal, not a macOS verdict. `pending`/unknown → nil.
    static func severity(forTier tier: String) -> CompatibilityFinding.Severity? {
        switch tier.lowercased() {
        case "platinum", "gold": .info
        case "silver", "bronze", "borked": .caveat
        default: nil
        }
    }

    static func finding(from summary: ProtonDBSummary, appID: Int) -> CompatibilityFinding? {
        guard let severity = severity(forTier: summary.tier) else { return nil }
        let rated = summary.total.map { " (\($0) report\($0 == 1 ? "" : "s"))" } ?? ""
        return CompatibilityFinding(
            id: "protondb",
            severity: severity,
            title: "ProtonDB: \(summary.tier.capitalized)\(rated)",
            detail: detail(forTier: summary.tier),
            suggestion: "Crowd data from Linux/Proton — a directional hint, not a macOS guarantee."
        )
    }

    private static func detail(forTier tier: String) -> String {
        switch tier.lowercased() {
        case "platinum": "Runs flawlessly out of the box on Proton — an excellent sign it'll behave here too."
        case "gold": "Runs great on Proton after minor tweaks. Good odds on macOS Wine."
        case "silver": "Runs on Proton with some tweaks and minor issues. Expect to fiddle a little."
        case "bronze": "Runs on Proton but with significant problems. May need real effort here."
        case "borked": "Reported broken on Proton. It may not run under macOS Wine either — try, but temper expectations."
        default: ""
        }
    }
}

/// On-disk cache of fetched ProtonDB summaries, so a game is fetched once and
/// reused offline. Lives under `AppPaths.quirkCache/protondb`.
struct ProtonDBCache: Sendable {
    let directory: URL

    init(directory: URL = AppPaths.quirkCache.appending(path: "protondb", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    private struct Record: Codable { let fetchedAt: Date; let summary: ProtonDBSummary }

    private func file(_ appID: Int) -> URL { directory.appending(path: "\(appID).json") }

    /// A cached summary if present and younger than `maxAge` (default 7 days).
    func cached(appID: Int, maxAge: TimeInterval = 7 * 24 * 3600, now: Date = .now) -> ProtonDBSummary? {
        guard let data = try? Data(contentsOf: file(appID)),
              let record = try? JSONDecoder.fableDates.decode(Record.self, from: data),
              now.timeIntervalSince(record.fetchedAt) < maxAge else { return nil }
        return record.summary
    }

    func store(_ summary: ProtonDBSummary, appID: Int, now: Date = .now) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let record = Record(fetchedAt: now, summary: summary)
        try? JSONEncoder.fableDates.encode(record).write(to: file(appID), options: .atomic)
    }
}

private extension JSONDecoder {
    static var fableDates: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }
}
private extension JSONEncoder {
    static var fableDates: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }
}
