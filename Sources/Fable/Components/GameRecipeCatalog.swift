import Foundation

/// A validated, known-good setup for a specific game: the backend +
/// performance + a human note. The seed of Fable's compatibility knowledge
/// base — a recipe beats heuristics, and *adding a game is adding a line of
/// data*, not writing code, so the catalog can grow from community/agent
/// reports without touching logic.
struct GameRecipe: Codable, Hashable, Sendable {
    let name: String
    /// Lowercased executable basenames that identify this game.
    let executables: [String]
    let backend: GraphicsBackend
    let metalFX: Bool
    let frameRateCap: Int?
    let note: String

    /// The performance preset this recipe prescribes.
    var performance: PerformanceOptions {
        PerformanceOptions(metalHUD: false, metalFXUpscaling: metalFX, frameRateCap: frameRateCap)
    }

    /// A one-line summary of the prescribed config (for the banner).
    var configSummary: String {
        var parts = [backend.shortName]
        if let frameRateCap { parts.append("\(frameRateCap) fps cap") }
        if metalFX { parts.append("MetalFX") }
        return "Tested: " + parts.joined(separator: " + ") + "."
    }

    /// Surfaced through the existing compatibility banner as an info note.
    var finding: CompatibilityFinding {
        CompatibilityFinding(
            id: "recipe", severity: .info,
            title: "Known setup: \(name)", detail: note, suggestion: configSummary
        )
    }
}

enum GameRecipeCatalog {
    /// Curated setups validated on real hardware. Keyed by executable
    /// basename (lowercased). Grow this freely — it's pure data.
    static let all: [GameRecipe] = [
        GameRecipe(
            name: "Balatro", executables: ["balatro.exe"],
            backend: .sikarugir, metalFX: false, frameRateCap: nil,
            note: "LÖVE2D/SDL2 game, runs on the Sikarugir D3DMetal path inside a Steam bottle. Keep Retina mode OFF — SDL games render into a corner with it on."
        ),
        GameRecipe(
            name: "DEATHLOOP", executables: ["deathloop.exe"],
            backend: .sikarugir, metalFX: true, frameRateCap: 60,
            note: "D3D12 AAA. Cap to 60 + MetalFX to hold steady FPS against unified-memory creep over a long session; drop in-game texture quality a notch if it still decays."
        ),
        GameRecipe(
            name: "System Shock 2 (NewDark)", executables: ["ss2.exe", "shock2.exe"],
            backend: .dxvk, metalFX: false, frameRateCap: nil,
            note: "NewDark D3D9. DXVK is the reliable path on Apple Silicon — wined3d's GL doesn't recognize the Apple GPU. The Dark engine is framerate-sensitive, so cap FPS in-game."
        ),
        GameRecipe(
            name: "Ready or Not", executables: ["readyornot.exe", "readyornot-win64-shipping.exe"],
            backend: .sikarugir, metalFX: true, frameRateCap: 120,
            note: "UE4, launched through Steam in the bottle. Validated ~4 h on an M4 Pro (24 GB) at a 120 fps cap with MetalFX. If a long session starts to slip, drop the cap to 60 — same fix as DEATHLOOP."
        ),
    ]

    // Adding an entry: only from a REAL tested setup — read the bottle's
    // bottle.json (backend/override + performance) and game-stats.json
    // (tracked playtime), don't work from memory; configSummary literally
    // prints "Tested:". Never seed a recipe you can't defend with playtime.

    /// The recipe matching a game's executable path (by basename), if any.
    /// Robust to both `/` (Fable's stored form) and `\` (Windows) separators.
    static func recipe(forExecutablePath path: String) -> GameRecipe? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let exe = (normalized as NSString).lastPathComponent.lowercased()
        guard !exe.isEmpty else { return nil }
        return all.first { $0.executables.contains(exe) }
    }
}
