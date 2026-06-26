import Foundation

/// Central, documented home for Fable's Wine environment "quirks" — the
/// hard-won env-var fixes that get Windows games running under Rosetta + Wine
/// on Apple Silicon.
///
/// Each fix lives here *with its rationale*, so debugging a regression,
/// upgrading the Wine build, or agent-driven maintenance touches ONE file
/// instead of hunting through every manager. The backend managers
/// (GPTK/DXVK/DXMT/Sikarugir/CrossOver) layer their own renderer vars on top of
/// this base; those stay with their backend since they're backend-specific.
///
/// Deeper notes live in memory: `fable-msync-iocp-spin`, `rosetta-avx-flag`,
/// `fable-retina-pixelation-fix`, `fable-cef-dwrite-trap`. See also
/// `docs/wine-quirks.md` for the human-readable map.
enum WineEnv {

    // MARK: - Variable names
    // Centralized so a typo can't silently disable a fix.

    static let prefix = "WINEPREFIX"
    static let debug = "WINEDEBUG"
    static let dllOverrides = "WINEDLLOVERRIDES"

    // MARK: - WINEDEBUG profiles

    /// Prefix provisioning: fully silent — diagnostics add nothing while we're
    /// just creating a prefix.
    static let debugSilent = "-all"

    /// Launch & install default: keep real `err:`/crash output for diagnosis,
    /// but silence the msync `err:msync:server_register_wait` line that Wine
    /// logs **per frame** — one stable DEATHLOOP session wrote a 25 GB log.
    /// It's an `err`, so plain `fixme-all` doesn't stop it; the `-msync`
    /// disables that channel specifically. Any new msync-based Wine needs this
    /// or it eats the disk. See memory: `fable-msync-iocp-spin`.
    static let debugDiagnostic = "fixme-all,-msync"

    // MARK: - Always-on base fixes

    /// Skip the Mono/Gecko installer dialogs so prefix creation never blocks on
    /// UI. Games that need .NET get it through the bottle's dependencies later.
    static let skipMonoGeckoDialogs = "mscoree,mshtml="

    /// Makes Rosetta 2 advertise AVX/AVX2/FMA/BMI2 to the translated x86 game.
    /// Default Rosetta hides them, so a game whose CPU check requires AVX aborts
    /// with int3 before it ever renders — an invisible failure that looks like a
    /// graphics bug. macOS 15+/26 supports this opt-in; no-op on native-arm64
    /// Wine. Verified 2026-06-15 (unset → AVX=0; =1 → AVX/AVX2/FMA/BMI2=1).
    /// See memory: `rosetta-avx-flag`.
    static let advertiseAVX = (key: "ROSETTA_ADVERTISE_AVX", value: "1")

    /// SDL's dedicated HIDAPI drivers for PlayStation pads (DualSense /
    /// DualShock 4), so SDL-based games recognize the controller and its layout.
    /// Harmless for Xbox/other pads (Wine maps those to XInput) and for
    /// non-controller runs.
    static let playstationControllers = [
        "SDL_JOYSTICK_HIDAPI_PS4": "1",
        "SDL_JOYSTICK_HIDAPI_PS5": "1",
    ]

    /// The base environment every prefix and launch starts from: the prefix
    /// path, silent debug, and the always-on Rosetta / controller / dialog-skip
    /// fixes. Launch and install paths then bump `debug` to ``debugDiagnostic``
    /// (via ``diagnosticDebug(in:)``) and merge backend + per-game vars on top.
    static func base(prefix prefixURL: URL) -> [String: String] {
        var env = [
            Self.prefix: prefixURL.path,
            debug: debugSilent,
            dllOverrides: skipMonoGeckoDialogs,
            advertiseAVX.key: advertiseAVX.value,
        ]
        env.merge(playstationControllers) { _, new in new }
        return env
    }

    /// Flips a base environment to the diagnostic WINEDEBUG profile — what
    /// every launch/install path wants (real errors, no msync flood). One call
    /// instead of the magic string copy-pasted at each site.
    static func withDiagnosticDebug(_ environment: [String: String]) -> [String: String] {
        var env = environment
        env[debug] = debugDiagnostic
        return env
    }
}
