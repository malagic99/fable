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

/// A Wine prefix and its metadata. Stored on disk as
/// Bottles/<id>/bottle.json, with the prefix itself at Bottles/<id>/prefix.
struct Bottle: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var windowsVersion: WindowsVersion
    var createdAt: Date
    var games: [Game]

    init(
        id: UUID = UUID(),
        name: String,
        windowsVersion: WindowsVersion = .win10,
        createdAt: Date = .now,
        games: [Game] = []
    ) {
        self.id = id
        self.name = name
        self.windowsVersion = windowsVersion
        self.createdAt = createdAt
        self.games = games
    }
}
