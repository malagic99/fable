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
    /// Per-game DualSense trigger override. nil = inherit the bottle's profile.
    var triggerProfile: TriggerProfile?

    init(
        id: UUID = UUID(),
        name: String,
        executablePath: String,
        arguments: String = "",
        environment: [String: String] = [:],
        graphicsBackend: GraphicsBackend? = nil,
        triggerProfile: TriggerProfile? = nil
    ) {
        self.id = id
        self.name = name
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.graphicsBackend = graphicsBackend
        self.triggerProfile = triggerProfile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        executablePath = try container.decode(String.self, forKey: .executablePath)
        arguments = try container.decodeIfPresent(String.self, forKey: .arguments) ?? ""
        environment = try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        graphicsBackend = try container.decodeIfPresent(GraphicsBackend.self, forKey: .graphicsBackend)
        triggerProfile = try container.decodeIfPresent(TriggerProfile.self, forKey: .triggerProfile)
    }

    /// The trigger profile actually in effect: the game's override, else the
    /// bottle's default.
    func effectiveTriggerProfile(bottleDefault: TriggerProfile) -> TriggerProfile {
        triggerProfile ?? bottleDefault
    }
}

/// Which translation layer renders a bottle's games.
///
/// **Backend matrix** — pick the path for the game (updated 2026-06):
///
/// | Game class                             | Backend      | Why                          |
/// |----------------------------------------|--------------|------------------------------|
/// | Older DirectX 9–11 (1999–2012)         | `.off`       | Wine's built-in wined3d is enough |
/// | DirectX 10/11 (2012–2020)              | `.dxmt`      | Best D3D11→Metal, modern Wine|
/// | DirectX 12 / modern AAA / Steam client | `.sikarugir` | Free matched Wine-10 + D3DMetal: modern SEH + D3D12→Metal, and the only free path that renders Steam's CEF |
/// | Vulkan-friendly / DXVK titles          | `.dxvk`      | DirectX→Vulkan→Metal, modern Wine |
/// | You already own CrossOver              | `.crossover` | Routes through its engine     |
/// | Legacy fallback                        | `.gptk`      | Apple GPTK on Wine 7.7 — superseded by `.sikarugir` for anything needing modern SEH |
///
/// NB: `rawValue`s are persisted in every bottle.json — never rename a
/// case. Only the user-facing displayName/shortName below should change.
enum GraphicsBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Wine's built-in wined3d (DirectX→OpenGL→Metal). For older games.
    case off
    /// DXMT: D3D10/11 → Metal. Runs on the modern Wine (11.10).
    case dxmt
    /// Apple Game Porting Toolkit: DirectX → Metal via D3DMetal, but on
    /// the GPTK Wine (7.7 base) — can't unwind modern MSVC SEH, so it's a
    /// LEGACY fallback now superseded by `.sikarugir` for modern titles.
    case gptk
    /// DXVK + vkd3d-proton: D3D9/10/11 via DXVK and D3D12 via vkd3d,
    /// both → Vulkan → MoltenVK → Metal, on modern Wine (11.10). Higher
    /// overhead than D3DMetal but a solid Vulkan-path alternative.
    case dxvk
    /// Route through the user's installed CrossOver (when present).
    /// Same D3DMetal class of result; requires the paid app.
    case crossover
    /// Sikarugir: free matched Wine-10.0 + D3DMetal pair. Modern SEH
    /// (unwinds modern C++ throws GPTK's wine-7.7 can't) AND real
    /// D3D12→Metal — and, with the D3DMetal framework wired, the only
    /// free backend that renders Steam's CEF client. The modern flagship.
    case sikarugir

    var id: String { rawValue }

    /// One-line label for the backend picker: name — what it does (note).
    /// The descriptive tail is translated; the backend names inside stay
    /// as-is (proper nouns) within each localized string.
    var displayName: String { L10n.string("backend.display.\(rawValue)") }

    /// Compact label for inline UI ("DXMT", "GPTK", "DXVK", "CrossOver",
    /// "Built-in"). `.off` is NOT "Wine" — everything here is Wine; .off means
    /// Wine's built-in D3D path. Only `.off` translates; the rest are proper
    /// nouns identical in every language.
    var shortName: String {
        switch self {
        case .off: L10n.string("backend.short.off")
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
    /// winemac.drv Retina mode. Crisps HiDPI UI (Steam's CEF, launchers)
    /// but renders many non-HiDPI-aware games (SDL/GL) into a corner with
    /// mismatched input — so it defaults OFF, since the point is games.
    var retinaMode: Bool
    /// Default DualSense adaptive-trigger profile for this bottle's games.
    /// A per-game override on `Game` wins over this.
    var triggerProfile: TriggerProfile

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
        installedWinetricksVerbs: Set<String> = [],
        retinaMode: Bool = false,
        triggerProfile: TriggerProfile = TriggerProfile()
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
        self.retinaMode = retinaMode
        self.triggerProfile = triggerProfile
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
        // Added post-launch; older bottles default to off (matches the
        // winemac.drv default and keeps existing games rendering correctly).
        retinaMode = try container.decodeIfPresent(Bool.self, forKey: .retinaMode) ?? false
        triggerProfile = try container.decodeIfPresent(TriggerProfile.self, forKey: .triggerProfile) ?? TriggerProfile()
    }
}
