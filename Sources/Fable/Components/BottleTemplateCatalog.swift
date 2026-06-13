import Foundation

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

    var isVanilla: Bool { dependencyIDs.isEmpty && winetricksVerbs.isEmpty }
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
            winetricksVerbs: ["corefonts", "steam"]
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
