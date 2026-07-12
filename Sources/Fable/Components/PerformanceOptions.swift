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

    /// Sensible performance defaults for a backend ON THIS HARDWARE, so heavy
    /// modern titles hold a steady frame rate instead of starting smooth and
    /// decaying. Applied to fresh bottles (and on backend switch) only when
    /// the user hasn't customized performance yet.
    ///
    /// The hardware lever: a Max/Ultra with 48 GB+ has genuine headroom (120
    /// cap, no forced upscale); a Pro-class or 24 GB machine gets the steady
    /// 60 + MetalFX (unified memory is shared with the GPU); 16 GB or less
    /// leans on MetalFX everywhere it exists.
    static func recommended(
        for backend: GraphicsBackend,
        hardware: HardwareProfile = .current
    ) -> PerformanceOptions {
        let roomy = (hardware.chipTier == .max || hardware.chipTier == .ultra)
            && hardware.memoryGB >= 48
        switch backend {
        case .sikarugir, .gptk:
            // D3DMetal AAA path: upscale + cap to ease sustained GPU load and
            // unified-memory pressure — unless the machine has real headroom.
            return roomy
                ? PerformanceOptions(metalHUD: false, metalFXUpscaling: false, frameRateCap: 120)
                : PerformanceOptions(metalHUD: false, metalFXUpscaling: true, frameRateCap: 60)
        case .dxmt, .dxvk:
            // Translation backends honor the cap (MetalFX is D3DMetal-only).
            return PerformanceOptions(
                metalHUD: false, metalFXUpscaling: false, frameRateCap: roomy ? 120 : 60
            )
        case .off, .crossover:
            // wined3d (old, light games) and CrossOver (manages its own) keep
            // the bare defaults.
            return PerformanceOptions()
        }
    }

    /// One honest sentence about why these are the defaults on this machine —
    /// shown under the Performance section. nil when there's nothing useful
    /// to say (backends Fable doesn't tune).
    static func hardwareAdvice(
        for backend: GraphicsBackend,
        hardware: HardwareProfile = .current
    ) -> String? {
        let roomy = (hardware.chipTier == .max || hardware.chipTier == .ultra)
            && hardware.memoryGB >= 48
        switch backend {
        case .sikarugir, .gptk:
            return roomy
                ? L10n.string("advice.hw.headroom", hardware.chipName, String(hardware.memoryGB))
                : L10n.string("advice.hw.d3dmetal", hardware.chipName, String(hardware.memoryGB))
        case .dxmt, .dxvk:
            return L10n.string("advice.hw.translation", hardware.chipName)
        case .off, .crossover:
            return nil
        }
    }

    /// The most stable config Fable knows for a backend — the one-click "Rock
    /// Solid" button. A 60 fps cap holds frame pacing steady (a locked 60 beats
    /// a flapping 60→72→55 fighting vsync), plus MetalFX on the D3DMetal path to
    /// ease GPU + unified-memory pressure over long sessions. Unlike
    /// ``recommended(for:)``, this is applied on demand even to a tuned bottle.
    static func rockSolid(for backend: GraphicsBackend) -> PerformanceOptions {
        switch backend {
        case .sikarugir, .gptk:
            return PerformanceOptions(metalHUD: false, metalFXUpscaling: true, frameRateCap: 60)
        case .dxmt, .dxvk, .off, .crossover:
            // MetalFX is D3DMetal-only; the cap still steadies everything else.
            return PerformanceOptions(metalHUD: false, metalFXUpscaling: false, frameRateCap: 60)
        }
    }

    /// Env additions that apply regardless of backend.
    func backendAgnosticEnvironment() -> [String: String] {
        metalHUD ? ["MTL_HUD_ENABLED": "1"] : [:]
    }

    /// Env additions specific to the GPTK/D3DMetal backend.
    ///
    /// Var names verified by strings-dump of every D3DMetal binary we ship —
    /// the previous D3DM_USE_METALFX_UPSCALER / D3DM_FRAME_RATE_LIMIT appear
    /// in none of them (silent no-ops). D3DM_MAX_FPS exists in GPTK 4.0+
    /// only; older D3DMetal ignores it, matching the old behavior. Full
    /// inventory: wine-quirks.md, "D3DMetal env vars".
    func gptkEnvironment() -> [String: String] {
        var env: [String: String] = [:]
        if metalFXUpscaling {
            env["D3DM_ENABLE_METALFX"] = "1"
        }
        if let frameRateCap, frameRateCap > 0 {
            env["D3DM_MAX_FPS"] = String(frameRateCap)
        }
        return env
    }
}
