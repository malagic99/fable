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
    /// Extra command-line arguments, shell-style ("-windowed \"two words\"").
    var arguments: String
    /// Extra environment variables applied at launch.
    var environment: [String: String]

    init(
        id: UUID = UUID(),
        name: String,
        executablePath: String,
        arguments: String = "",
        environment: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        executablePath = try container.decode(String.self, forKey: .executablePath)
        arguments = try container.decodeIfPresent(String.self, forKey: .arguments) ?? ""
        environment = try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
    }
}

/// Lifecycle of a bottle's Wine prefix.
enum BottleStatus: String, Codable, Sendable {
    /// Created, but Wine prefix initialization hasn't finished.
    case provisioning
    /// Prefix exists and is usable.
    case ready
    /// Provisioning was interrupted (app quit mid-setup). Repairable.
    case broken
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
    var dxmtEnabled: Bool
    var dxmtConfig: DXMTConfig

    init(
        id: UUID = UUID(),
        name: String,
        windowsVersion: WindowsVersion = .win10,
        createdAt: Date = .now,
        status: BottleStatus = .provisioning,
        games: [Game] = [],
        dxmtEnabled: Bool = false,
        dxmtConfig: DXMTConfig = DXMTConfig()
    ) {
        self.id = id
        self.name = name
        self.windowsVersion = windowsVersion
        self.createdAt = createdAt
        self.status = status
        self.games = games
        self.dxmtEnabled = dxmtEnabled
        self.dxmtConfig = dxmtConfig
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        windowsVersion = try container.decode(WindowsVersion.self, forKey: .windowsVersion)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        // Fields added after Day 2 get defaults so older bottles keep working.
        status = try container.decodeIfPresent(BottleStatus.self, forKey: .status) ?? .ready
        games = try container.decodeIfPresent([Game].self, forKey: .games) ?? []
        dxmtEnabled = try container.decodeIfPresent(Bool.self, forKey: .dxmtEnabled) ?? false
        dxmtConfig = try container.decodeIfPresent(DXMTConfig.self, forKey: .dxmtConfig) ?? DXMTConfig()
    }
}
