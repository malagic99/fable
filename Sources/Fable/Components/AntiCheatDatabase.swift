import Foundation

/// Preemptive anti-cheat verdicts from the AreWeAntiCheatYet dataset — the
/// single most troubleshooting-saving quirk source, because it tells you a
/// game's anti-cheat won't run on Wine *before* you install 50 GB and find out
/// the hard way. The same kernel-anti-cheat limits that block a game on
/// Linux/Proton block it on macOS Wine.
///
/// First (offline) source of the quirk system. Schema verified against a real
/// dataset (1166 entries): a flat array of `{ name, status, anticheats, … }`.
/// `status` ∈ Supported / Running / Planned / Configuration / Broken / Denied /
/// Unknown.
struct AntiCheatDatabase: Sendable {
    struct Entry: Sendable, Hashable {
        let name: String
        /// Raw upstream status (e.g. "Denied", "Broken", "Supported").
        let status: String
        /// Anti-cheat product names, e.g. ["Easy Anti-Cheat", "BattlEye"].
        let anticheats: [String]
    }

    private let byNormalizedName: [String: Entry]

    var count: Int { byNormalizedName.count }

    init(entries: [Entry]) {
        byNormalizedName = Dictionary(
            entries.map { (Self.normalize($0.name), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// The entry for a game by name (™/® and punctuation-insensitive).
    func entry(forGameNamed name: String) -> Entry? {
        byNormalizedName[Self.normalize(name)]
    }

    /// A compatibility finding for a game, or nil when it's absent or its
    /// status carries no actionable signal (Unknown).
    func finding(forGameNamed name: String) -> CompatibilityFinding? {
        guard let entry = entry(forGameNamed: name),
              let severity = Self.severity(for: entry.status) else { return nil }
        let names = entry.anticheats.isEmpty ? "" : " (\(entry.anticheats.joined(separator: ", ")))"
        return CompatibilityFinding(
            id: "anticheat-db",
            severity: severity,
            title: Self.title(for: entry.status) + names,
            detail: Self.detail(for: entry.status),
            suggestion: Self.suggestion(for: entry.status)
        )
    }

    // MARK: Loading

    /// Parses an AreWeAntiCheatYet JSON file. Tolerant of the loose schema —
    /// ignores entries missing a name or status. nil if the file is unreadable.
    static func load(from url: URL) -> AntiCheatDatabase? {
        guard let data = try? Data(contentsOf: url),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        let entries = array.compactMap { row -> Entry? in
            guard let name = row["name"] as? String, !name.isEmpty,
                  let status = row["status"] as? String, !status.isEmpty else { return nil }
            let anticheats = (row["anticheats"] as? [String]) ?? []
            return Entry(name: name, status: status, anticheats: anticheats)
        }
        return entries.isEmpty ? nil : AntiCheatDatabase(entries: entries)
    }

    /// The snapshot that ships inside Fable: AreWeAntiCheatYet's games.json
    /// (MIT, © Starz0r, Curve — licence beside it in the bundle) at commit
    /// 6c26305efc3d, trimmed to name, status and anti-cheat products. Before
    /// it was bundled, nothing wrote the cache below, so the "before you
    /// install 50 GB" warning only worked on Macs that happened to have Heroic.
    static var bundledSnapshot: URL? {
        Bundle.fableResources.url(forResource: "areweanticheatyet", withExtension: "json")
    }

    /// Loads from the first available known location: Fable's own cache (a
    /// future online refresh writes here), then the bundled snapshot. A local
    /// Heroic copy is the last resort for a build missing its resources.
    static func loadFromDefaultLocations(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> AntiCheatDatabase? {
        let candidates = [
            AppPaths.quirkCache.appending(path: "areweanticheatyet.json"),
            bundledSnapshot,
            home.appending(path: "Library/Application Support/heroic/areweanticheatyet.json"),
        ].compactMap { $0 }
        return candidates.lazy.compactMap(load(from:)).first
    }

    // MARK: Mapping

    /// Maps an upstream status to a finding severity. nil = no actionable
    /// signal (Unknown / unrecognized → don't surface anything).
    ///
    /// The dataset rates games for Linux/Proton, and its good news doesn't
    /// carry over: "Supported" means the developer enabled the anti-cheat's
    /// Linux runtime, which Proton loads and macOS Wine can't. So on a Mac
    /// that's a caveat (online play is unlikely), not a green light.
    static func severity(for status: String) -> CompatibilityFinding.Severity? {
        switch status.lowercased() {
        case "denied", "broken": .knownBlocker
        case "planned", "configuration", "supported": .caveat
        case "running": .info
        default: nil
        }
    }

    private static func title(for status: String) -> String {
        switch status.lowercased() {
        case "denied", "broken": "Anti-cheat blocks this game on Wine (\(status))"
        case "supported": "Anti-cheat works on Linux, not on Mac (Supported)"
        case "planned", "configuration": "Anti-cheat needs setup (\(status))"
        default: "Anti-cheat runs under Wine (\(status))"
        }
    }

    private static func detail(for status: String) -> String {
        switch status.lowercased() {
        case "denied":
            "The developer has turned this anti-cheat off for Linux and Wine. The game refuses to start online — or at all — and can ban accounts that try. The same applies on a Mac."
        case "broken":
            "This anti-cheat doesn't work under Wine on Linux (it needs kernel-level access Wine can't give), and the same is true on a Mac."
        case "supported":
            "On Linux the developer enabled the anti-cheat for Proton, which loads a Linux version of it. macOS Wine can't load that, so online play is unlikely to work on a Mac. Single-player often still does: the anti-cheat usually falls back to an offline mode."
        case "planned", "configuration":
            "Support is partial — it may need a launch option or a specific configuration, and isn't guaranteed."
        default:
            "This game's anti-cheat runs under Wine on Linux without special support — a good sign for a Mac too."
        }
    }

    private static func suggestion(for status: String) -> String {
        switch status.lowercased() {
        case "denied", "broken":
            "This game won't run in Fable. A cloud service such as GeForce Now, or streaming from a Windows PC, works instead."
        case "supported":
            "Expect single-player at best. If online play is why you want it, check before downloading."
        case "planned", "configuration":
            "Check AreWeAntiCheatYet for the exact launch option this title needs."
        default:
            ""
        }
    }

    /// Normalizes a game name for matching: lowercased, ™/® stripped, punctuation
    /// folded to spaces, whitespace collapsed.
    static func normalize(_ name: String) -> String {
        let lowered = name.lowercased()
        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }
}
