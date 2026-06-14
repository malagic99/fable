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
    /// Per-game graphics override. nil = inherit the bottle's backend
    /// (lets a D3D9 and a D3D11 game share one bottle without fighting).
    var graphicsBackend: GraphicsBackend?

    init(
        id: UUID = UUID(),
        name: String,
        executablePath: String,
        arguments: String = "",
        environment: [String: String] = [:],
        graphicsBackend: GraphicsBackend? = nil
    ) {
        self.id = id
        self.name = name
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.graphicsBackend = graphicsBackend
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        executablePath = try container.decode(String.self, forKey: .executablePath)
        arguments = try container.decodeIfPresent(String.self, forKey: .arguments) ?? ""
        environment = try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        graphicsBackend = try container.decodeIfPresent(GraphicsBackend.self, forKey: .graphicsBackend)
    }
}

/// Which translation layer renders a bottle's games.
///
/// **Backend matrix** — pick the right path for the era:
///
/// | Game class                          | Backend       | Why                                |
/// |-------------------------------------|---------------|------------------------------------|
/// | 1999-2010 D3D9                      | `.off`        | Wine 11.10 built-in works           |
/// | 2010-2018 D3D11 AAA                 | `.dxmt`       | Best D3D11→Metal path               |
/// | 2018-2024 D3D12 (no Streamline)     | `.gptk`       | D3DMetal optimization               |
/// | 2024+ D3D12 + Streamline / SEH-heavy| `.dxvk`       | Modern Wine SEH handles unwinding   |
/// | Hardest cases (modern AAA)          | `.crossover`  | CrossOver wine 9+ + licensed D3DMetal |
enum GraphicsBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Wine's built-in rendering (D3D9-era games, safest).
    case off
    /// DXMT: D3D11/10 → Metal. Runs on the modern Wine (11.10).
    case dxmt
    /// Game Porting Toolkit: D3D9–12 → Metal via Apple's D3DMetal,
    /// running on the GPTK Wine (7.7 base). Best perf for the
    /// titles whose age + features GPTK was designed around.
    case gptk
    /// DXVK + vkd3d-proton: D3D9/10/11 via DXVK and D3D12 via
    /// vkd3d-proton, both → Vulkan → MoltenVK → Metal, on modern Wine
    /// (11.10). Higher overhead than D3DMetal but supports modern SEH
    /// unwinding that GPTK's wine 7.7 fails on.
    case dxvk
    /// Route through the user's installed CrossOver (when present).
    /// CrossOver licensed D3DMetal from Apple and rebuilt it against
    /// wine 9+ source — modern SEH + the optimization layer in one.
    case crossover
    /// Sikarugir: wine-10.0 + D3DMetal recompiled against it. The free
    /// matched pair — modern SEH (unwinds modern C++ throws GPTK's
    /// wine-7.7 can't) AND real D3D12→Metal. Best path for 2024+ D3D12
    /// games. Discovered from the user's Sikarugir install.
    case sikarugir

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: "Wine built-in (D3D9 era)"
        case .dxmt: "DXMT — DirectX 11 via Metal"
        case .gptk: "Game Porting Toolkit — DirectX 12 via Metal"
        case .dxvk: "DXVK + vkd3d — DirectX via Vulkan (modern Wine)"
        case .crossover: "CrossOver — D3D9–12 via licensed D3DMetal"
        case .sikarugir: "Sikarugir — D3D12 via D3DMetal on modern Wine"
        }
    }

    /// Compact label for inline UI ("DXMT", "GPTK", "DXVK", "CrossOver", "Wine").
    var shortName: String {
        switch self {
        case .off: "Wine"
        case .dxmt: "DXMT"
        case .gptk: "GPTK"
        case .dxvk: "DXVK"
        case .crossover: "CrossOver"
        case .sikarugir: "Sikarugir"
        }
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
    var graphicsBackend: GraphicsBackend
    var dxmtConfig: DXMTConfig
    var performance: PerformanceOptions
    /// Winetricks verb slugs the user has installed in this bottle.
    /// Trusted from click history — verb-level detection isn't reliable.
    var installedWinetricksVerbs: Set<String>

    init(
        id: UUID = UUID(),
        name: String,
        windowsVersion: WindowsVersion = .win10,
        createdAt: Date = .now,
        status: BottleStatus = .provisioning,
        games: [Game] = [],
        graphicsBackend: GraphicsBackend = .off,
        dxmtConfig: DXMTConfig = DXMTConfig(),
        performance: PerformanceOptions = PerformanceOptions(),
        installedWinetricksVerbs: Set<String> = []
    ) {
        self.id = id
        self.name = name
        self.windowsVersion = windowsVersion
        self.createdAt = createdAt
        self.status = status
        self.games = games
        self.graphicsBackend = graphicsBackend
        self.dxmtConfig = dxmtConfig
        self.performance = performance
        self.installedWinetricksVerbs = installedWinetricksVerbs
    }

    private enum LegacyKeys: String, CodingKey {
        case dxmtEnabled
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
        if let backend = try container.decodeIfPresent(GraphicsBackend.self, forKey: .graphicsBackend) {
            graphicsBackend = backend
        } else {
            // Pre-GPTK bottles stored a DXMT boolean.
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            let dxmtEnabled = try legacy.decodeIfPresent(Bool.self, forKey: .dxmtEnabled) ?? false
            graphicsBackend = dxmtEnabled ? .dxmt : .off
        }
        dxmtConfig = try container.decodeIfPresent(DXMTConfig.self, forKey: .dxmtConfig) ?? DXMTConfig()
        if let perf = try container.decodeIfPresent(PerformanceOptions.self, forKey: .performance) {
            performance = perf
        } else {
            // Pre-Day 12 bottles only carried a frame-rate cap on DXMTConfig.
            var migrated = PerformanceOptions()
            migrated.frameRateCap = dxmtConfig.maxFrameRate
            performance = migrated
        }
        installedWinetricksVerbs = try container.decodeIfPresent(
            Set<String>.self, forKey: .installedWinetricksVerbs
        ) ?? []
    }
}
