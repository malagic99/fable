import Foundation

/// Per-bottle performance toggles applied at game launch via env vars.
/// Backend-agnostic — the launcher decides which ones make sense per
/// graphics backend (e.g. MetalFX only matters when GPTK is active).
struct PerformanceOptions: Codable, Hashable, Sendable {
    /// Apple's built-in Metal performance HUD (FPS / frametime / GPU%).
    /// Activated by `MTL_HUD_ENABLED=1` in the game's environment.
    var metalHUD: Bool = false

    /// GPTK/D3DMetal 4 MetalFX upscaler. Lets games render at lower
    /// internal resolution and upscale via Metal's neural upscaler.
    /// Only honored by the GPTK backend.
    var metalFXUpscaling: Bool = false

    /// Frame-rate cap in FPS. nil = uncapped.
    /// DXMT: routed through `DXMT_CONFIG=dxgi.maxFrameRate`.
    /// GPTK: routed through `D3DM_FRAME_RATE_LIMIT`.
    var frameRateCap: Int?

    /// Env additions that apply regardless of backend.
    func backendAgnosticEnvironment() -> [String: String] {
        metalHUD ? ["MTL_HUD_ENABLED": "1"] : [:]
    }

    /// Env additions specific to the GPTK/D3DMetal backend.
    func gptkEnvironment() -> [String: String] {
        var env: [String: String] = [:]
        if metalFXUpscaling {
            env["D3DM_USE_METALFX_UPSCALER"] = "1"
        }
        if let frameRateCap, frameRateCap > 0 {
            env["D3DM_FRAME_RATE_LIMIT"] = String(frameRateCap)
        }
        return env
    }
}
