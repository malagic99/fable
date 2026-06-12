import Foundation

/// Windows version a bottle reports to programs (applied via winecfg on Day 3).
enum WindowsVersion: String, Codable, CaseIterable, Identifiable, Sendable {
    case win11
    case win10
    case win7

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .win11: "Windows 11"
        case .win10: "Windows 10"
        case .win7: "Windows 7"
        }
    }
}

/// A game installed inside a bottle. Populated by the game installer (Day 4).
struct Game: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// Path of the .exe relative to the bottle's C: drive.
    var executablePath: String

    init(id: UUID = UUID(), name: String, executablePath: String) {
        self.id = id
        self.name = name
        self.executablePath = executablePath
    }
}

/// Lifecycle of a bottle's Wine prefix.
enum BottleStatus: String, Codable, Sendable {
    /// Created, but Wine prefix initialization hasn't finished.
    case provisioning
    /// Prefix exists and is usable.
    case ready
}

/// A Wine prefix and its metadata. Stored on disk as
/// Bottles/<id>/bottle.json, with the prefix itself at Bottles/<id>/prefix.
struct Bottle: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var windowsVersion: WindowsVersion
    var createdAt: Date
    var status: BottleStatus
    var games: [Game]

    init(
        id: UUID = UUID(),
        name: String,
        windowsVersion: WindowsVersion = .win10,
        createdAt: Date = .now,
        status: BottleStatus = .provisioning,
        games: [Game] = []
    ) {
        self.id = id
        self.name = name
        self.windowsVersion = windowsVersion
        self.createdAt = createdAt
        self.status = status
        self.games = games
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        windowsVersion = try container.decode(WindowsVersion.self, forKey: .windowsVersion)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        // Bottles written before status existed are usable as-is.
        status = try container.decodeIfPresent(BottleStatus.self, forKey: .status) ?? .ready
        games = try container.decodeIfPresent([Game].self, forKey: .games) ?? []
    }
}
