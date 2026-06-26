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

    /// Loads from the first available known location: Fable's own cache (the
    /// online refresh will write here), then a local Heroic install's copy.
    static func loadFromDefaultLocations(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> AntiCheatDatabase? {
        let candidates = [
            AppPaths.quirkCache.appending(path: "areweanticheatyet.json"),
            home.appending(path: "Library/Application Support/heroic/areweanticheatyet.json"),
        ]
        return candidates.lazy.compactMap(load(from:)).first
    }

    // MARK: Mapping

    /// Maps an upstream status to a finding severity. nil = no actionable
    /// signal (Unknown / unrecognized → don't surface anything).
    static func severity(for status: String) -> CompatibilityFinding.Severity? {
        switch status.lowercased() {
        case "denied", "broken": .knownBlocker
        case "planned", "configuration": .caveat
        case "supported", "running": .info
        default: nil
        }
    }

    private static func title(for status: String) -> String {
        switch status.lowercased() {
        case "denied", "broken": "Anti-cheat won't run on Wine: \(status)"
        case "planned", "configuration": "Anti-cheat needs setup: \(status)"
        default: "Anti-cheat works on Wine: \(status)"
        }
    }

    private static func detail(for status: String) -> String {
        switch status.lowercased() {
        case "denied":
            "The developer has explicitly disabled this anti-cheat on Linux/Wine. It will refuse to run or ban you — the same applies on macOS Wine."
        case "broken":
            "This anti-cheat is known not to work on Linux/Wine (kernel-level enforcement Wine can't provide). It applies identically on macOS."
        case "planned", "configuration":
            "Anti-cheat support is partial — it may need a launch option or a specific config, and isn't guaranteed."
        default:
            "This game's anti-cheat is reported working on Linux/Wine — a good sign it'll behave on macOS too."
        }
    }

    private static func suggestion(for status: String) -> String {
        switch status.lowercased() {
        case "denied", "broken":
            "This game can't run on Fable today. Consider GeForce Now or another cloud-streaming service."
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
