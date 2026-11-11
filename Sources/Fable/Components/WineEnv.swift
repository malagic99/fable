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

    /// Skip the Gecko (embedded-IE) installer dialog so prefix creation never
    /// blocks on UI. Deliberately does NOT disable `mscoree`: a bottle with a
    /// real Microsoft .NET runtime installed needs Wine's mscoree to bootstrap
    /// IL assemblies, and disabling it breaks every .NET (Core) 6/7/8 app with
    /// "System.Runtime.dll: module not found". The Mono dialog is a rarer,
    /// non-fatal, .NET-Framework-only prompt — skipped instead only during
    /// unattended prefix init (see `WineEnv.provisioning`), where a blocking
    /// modal would actually break setup.
    static let skipGeckoDialog = "mshtml="

    /// Prefix-init only: also suppress the Mono dialog so `wineboot --init`
    /// stays unattended. Not used at game launch — see `skipGeckoDialog`.
    static let skipMonoGeckoDialogs = "mscoree,mshtml="

    /// .NET (Core) on Wine, always-on and inert for everything else:
    /// - USENLS routes globalization through Wine's Windows NLS instead of
    ///   .NET's bundled ICU, which fails to load on Wine ("Could not load ICU
    ///   data") and otherwise crashes every WPF/.NET-Core app on start.
    /// - EnableWriteXorExecute=0 keeps the JIT working under Rosetta + Wine.
    /// Both are read only by the .NET runtime; native games ignore them.
    static let dotnetCoreOnWine: [String: String] = [
        "DOTNET_SYSTEM_GLOBALIZATION_USENLS": "1",
        "DOTNET_EnableWriteXorExecute": "0",
    ]

    /// Makes Rosetta 2 advertise AVX/AVX2/FMA/BMI2 to the translated x86 game.
    /// Default Rosetta hides them, so a game whose CPU check requires AVX aborts
    /// with int3 before it ever renders — an invisible failure that looks like a
    /// graphics bug. macOS 15+/26 supports this opt-in. Verified 2026-06-15
    /// (unset → AVX=0; =1 → AVX/AVX2/FMA/BMI2=1). Meaningless without Rosetta,
    /// so ``base(prefix:layout:)`` only sets it for a translated host.
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
    ///
    /// `layout` decides whether the Rosetta-only vars are set at all. It
    /// defaults to ``WineLayout/rosetta`` — every backend shipping today.
    static func base(prefix prefixURL: URL, layout: WineLayout = .rosetta) -> [String: String] {
        var env = [
            Self.prefix: prefixURL.path,
            debug: debugSilent,
            dllOverrides: skipGeckoDialog,
        ]
        // Asking Rosetta to advertise AVX only means something when Rosetta is
        // in the picture. On a native-arm64 Wine the var is inert noise, and
        // leaving it set would make logs lie about how the game ran.
        if layout.isTranslatedHost {
            env[advertiseAVX.key] = advertiseAVX.value
        }
        env.merge(playstationControllers) { _, new in new }
        env.merge(dotnetCoreOnWine) { _, new in new }
        return env
    }

    /// Prefix-creation environment: the base plus the Mono-dialog skip so
    /// `wineboot --init` never stalls on a modal. Launch never uses this.
    static func provisioning(prefix prefixURL: URL, layout: WineLayout = .rosetta) -> [String: String] {
        var env = base(prefix: prefixURL, layout: layout)
        env[dllOverrides] = skipMonoGeckoDialogs
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

    // MARK: - Visual C++ runtime

    /// The DLLs Microsoft's VC++ 2015–2022 redistributable installs and Wine
    /// also builds in — the set `winetricks vcrun2022` switches to native.
    static let visualCppRuntimeDLLs = [
        "concrt140", "msvcp140", "msvcp140_1", "msvcp140_2", "msvcp140_atomic_wait",
        "msvcp140_codecvt_ids", "vcamp140", "vccorlib140", "vcomp140",
        "vcruntime140", "vcruntime140_1",
    ]

    /// `native,builtin` for the VC++ runtime when the bottle has Microsoft's.
    ///
    /// Installing the redistributable puts Microsoft's DLLs in system32, but
    /// Wine still loads its own same-named builtins first unless told
    /// otherwise — so games run on Wine's runtime anyway, and launchers that
    /// read the runtime's version find none. Unreal's bootstrap launcher
    /// (STALKER 2, 2026-11-03) does exactly that with `msvcp140_2.dll` and
    /// shows "Microsoft Visual C++ Runtime is required" though it's
    /// installed. nil when the bottle only has Wine's own copies.
    static func visualCppNativeOverride(driveC: URL) -> String? {
        let candidates = ["windows/system32/msvcp140.dll", "windows/syswow64/msvcp140.dll"]
        guard candidates.contains(where: { isMicrosoftDLL(driveC.appending(path: $0)) }) else { return nil }
        return visualCppRuntimeDLLs.joined(separator: ",") + "=n,b"
    }

    /// True for a DLL on disk that isn't one of Wine's: Wine stamps its
    /// builtins and placeholders in the DOS stub ("Wine builtin DLL").
    static func isMicrosoftDLL(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 128), head.count >= 64 else { return false }
        return head.range(of: Data("Wine builtin DLL".utf8)) == nil
            && head.range(of: Data("Wine placeholder DLL".utf8)) == nil
    }

    /// Adds `override` to a WINEDLLOVERRIDES value without a stray separator.
    static func appendingOverride(_ override: String, to existing: String?) -> String {
        guard let existing, !existing.isEmpty else { return override }
        return existing + ";" + override
    }

    /// Layers a user's WINEDLLOVERRIDES onto the one Fable composed, instead
    /// of replacing it. Replacing used to drop every override the backend
    /// needs — D3DMetal's builtins, the Mono/Gecko dialog skip — whenever a
    /// game set even one DLL. DLLs the user names are taken out of the base
    /// first, so their setting wins (Wine doesn't define which of two entries
    /// for the same DLL applies).
    static func mergingDLLOverrides(_ user: String, into base: String?) -> String {
        func entries(_ value: String) -> [(dlls: [String], mode: String)] {
            value.split(separator: ";").compactMap { item in
                // Keep an empty name part ("=n"), so a mode is never read as a DLL.
                let parts = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let dlls = parts[0].split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                guard !dlls.isEmpty else { return nil }
                let mode = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
                return (dlls, mode)
            }
        }
        let userEntries = entries(user)
        let named = Set(userEntries.flatMap(\.dlls).map { $0.lowercased() })
        let kept = entries(base ?? "").compactMap { entry -> (dlls: [String], mode: String)? in
            let dlls = entry.dlls.filter { !named.contains($0.lowercased()) }
            return dlls.isEmpty ? nil : (dlls, entry.mode)
        }
        return (kept + userEntries)
            .map { $0.dlls.joined(separator: ",") + "=" + $0.mode }
            .joined(separator: ";")
    }

    // MARK: - Per-game overrides

    /// Names a per-game override may not set. A game's settings can arrive
    /// inside a shared `.fbottle`, and each of these makes the *native* side
    /// load a binary of the sender's choosing: dyld's `DYLD_*` inject a dylib
    /// into Wine itself; `WINELOADER`/`WINESERVER` name the Wine executables;
    /// `WINEDLLPATH` finds builtin DLLs and their unix-side libraries. Fable's
    /// own layers may still set them. Matched case-insensitively.
    static let refusedOverridePrefixes = ["DYLD_"]
    static let refusedOverrideNames: Set<String> = ["WINELOADER", "WINESERVER", "WINEDLLPATH"]

    /// True for a POSIX shell variable name: `[A-Za-z_][A-Za-z0-9_]*`. The
    /// desktop-shortcut script exports names unquoted, so nothing else is safe.
    static func isPlainVariableName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first,
              first == "_" || (first.isASCII && CharacterSet.letters.contains(first))
        else { return false }
        return name.unicodeScalars.allSatisfy {
            $0 == "_" || ($0.isASCII && CharacterSet.alphanumerics.contains($0))
        }
    }

    /// Splits per-game overrides into the ones applied and the names refused
    /// (sorted): any that isn't a plain variable name, and the loader
    /// variables above.
    static func screenedOverrides(
        _ overrides: [String: String]
    ) -> (applied: [String: String], refused: [String]) {
        var applied: [String: String] = [:]
        var refused: [String] = []
        for (name, value) in overrides {
            let upper = name.uppercased()
            if !isPlainVariableName(name)
                || refusedOverrideNames.contains(upper)
                || refusedOverridePrefixes.contains(where: upper.hasPrefix) {
                refused.append(name)
            } else {
                applied[name] = value
            }
        }
        return (applied, refused.sorted())
    }
}
