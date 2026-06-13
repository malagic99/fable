import Foundation

/// One game (typically a launcher: Steam, Epic, Battle.net) that a
/// template auto-registers after provisioning, if the executable lands
/// in drive_c.
struct GameRegistration: Hashable, Sendable {
    let name: String
    /// Path relative to the bottle's drive_c.
    let executablePath: String
    /// Default per-game launch arguments (shell-tokenized at launch).
    let arguments: String
}

/// A preset that picks a graphics backend and a starter pack of
/// dependencies + winetricks verbs for a freshly-created bottle.
/// Provisioning runs them sequentially after the prefix is initialized.
struct BottleTemplate: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let summary: String
    let graphicsBackend: GraphicsBackend
    /// Dependency ids from `DependencyCatalog.all` to install.
    let dependencyIDs: [String]
    /// Winetricks verb slugs to install after dependencies.
    let winetricksVerbs: [String]
    /// Games auto-added to the bottle after deps + verbs run.
    /// A registration is skipped silently if its executable didn't land.
    let gamesToRegister: [GameRegistration]

    init(
        id: String,
        name: String,
        summary: String,
        graphicsBackend: GraphicsBackend,
        dependencyIDs: [String],
        winetricksVerbs: [String],
        gamesToRegister: [GameRegistration] = []
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.graphicsBackend = graphicsBackend
        self.dependencyIDs = dependencyIDs
        self.winetricksVerbs = winetricksVerbs
        self.gamesToRegister = gamesToRegister
    }

    var isVanilla: Bool {
        dependencyIDs.isEmpty && winetricksVerbs.isEmpty && gamesToRegister.isEmpty
    }
}

enum BottleTemplateCatalog {
    /// Curated presets, ordered from "do nothing extra" to "most loaded".
    /// Indices used as the picker's stable identity.
    static let all: [BottleTemplate] = [
        BottleTemplate(
            id: "vanilla",
            name: "Vanilla",
            summary: "Bare prefix. Add dependencies later from the bottle's page.",
            graphicsBackend: .off,
            dependencyIDs: [],
            winetricksVerbs: []
        ),
        BottleTemplate(
            id: "classic-d3d9",
            name: "Classic Games (D3D9)",
            summary: "DirectX 9 runtime for 2000s-era games. Wine's built-in graphics.",
            graphicsBackend: .off,
            dependencyIDs: ["directx-jun2010", "openal"],
            winetricksVerbs: []
        ),
        BottleTemplate(
            id: "modern-dxmt",
            name: "Modern Games (DXMT)",
            summary: "DirectX 11 via DXMT. Visual C++ + OpenAL pre-installed.",
            graphicsBackend: .dxmt,
            dependencyIDs: ["vcredist-x64", "vcredist-x86", "openal"],
            winetricksVerbs: []
        ),
        BottleTemplate(
            id: "steam-ready",
            name: "Steam Ready",
            summary: "Steam client + Visual C++ + corefonts + DXMT.",
            graphicsBackend: .dxmt,
            dependencyIDs: ["vcredist-x64", "vcredist-x86"],
            winetricksVerbs: ["corefonts", "steam"],
            // Steam installs to "Program Files (x86)/Steam/Steam.exe" by
            // default. -no-cef-sandbox is required on macOS Wine (the
            // documented workaround for the CEF crash on launch).
            gamesToRegister: [
                GameRegistration(
                    name: "Steam",
                    executablePath: "Program Files (x86)/Steam/Steam.exe",
                    arguments: "-no-cef-sandbox"
                )
            ]
        ),
        BottleTemplate(
            id: "d3d12-gptk",
            name: "Cutting Edge (GPTK / D3D12)",
            summary: "Apple Game Porting Toolkit with D3DMetal 4. DX12 titles.",
            graphicsBackend: .gptk,
            dependencyIDs: ["vcredist-x64", "vcredist-x86"],
            winetricksVerbs: []
        ),
    ]

    static let `default` = all[0]
}
