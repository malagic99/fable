import Foundation

/// Fable Doctor — turns a game's Wine log into plain-language diagnoses. When a
/// game won't start or crashes, the log holds the tell (a missing DLL, an
/// anti-cheat, a backend mismatch); this matches the known signatures and says
/// what to do, so users stop guessing.
///
/// Pure + data-driven: a diagnosis is a rule, and adding one is adding a line.
/// Reuses `CompatibilityFinding` so the doctor's output renders like the rest of
/// Fable's compatibility surface.
enum GameDoctor {

    struct Rule {
        let id: String
        /// Lowercased substrings — any one present in the log triggers the rule.
        let needles: [String]
        let severity: CompatibilityFinding.Severity
        let title: String
        let detail: String
        let suggestion: String
    }

    /// Seed rules — grow freely, it's data. Ordered most-actionable first.
    static let rules: [Rule] = [
        Rule(id: "vcredist",
             needles: ["msvcp140", "vcruntime140", "msvcr120", "msvcr100", "vcomp140"],
             severity: .caveat,
             title: "Missing Visual C++ runtime",
             detail: "The game can't find a Microsoft Visual C++ runtime DLL (e.g. MSVCP140.dll).",
             suggestion: "Install the Visual C++ runtime in this bottle's Dependencies. Steam games install it automatically the next time you quit Steam."),
        Rule(id: "dotnet",
             needles: ["mscoree", "clr.dll", ".net framework", "mscorlib"],
             severity: .caveat,
             title: "Needs the .NET Framework runtime",
             detail: "The game tried to load the .NET Framework CLR. Wine ships Wine Mono — a free reimplementation that already provides .NET Framework 4.x — so this usually just works without installing anything.",
             suggestion: "Do NOT run the winetricks `dotnet48`/`dotnet40` verbs: Microsoft's installer doesn't work under Wine (especially 64-bit), and those verbs delete Wine Mono first — a failed run leaves the bottle with no .NET at all. If .NET seems broken, use the bottle's Repair to restore Wine Mono. (For modern .NET 6/7/8 apps, that's a different runtime — see the other Doctor note.)"),
        Rule(id: "dwrite-cef",
             needles: ["dwrite", "c0000135"],
             severity: .caveat,
             title: "DirectWrite / CEF startup error (c0000135)",
             detail: "A c0000135 around DWrite usually means a DLL override broke DirectWrite — Steam's CEF hard-needs it.",
             suggestion: "Never override `dwrite` to disabled for a Steam/CEF bottle. Reset DLL overrides for this bottle."),
        Rule(id: "anticheat",
             needles: ["easyanticheat", "battleye", "beservice", "vgc.exe", "vanguard"],
             severity: .knownBlocker,
             title: "Anti-cheat detected in the log",
             detail: "A kernel-level anti-cheat tried to load. These have no working Wine implementation.",
             suggestion: "This game can't run on macOS Wine. Consider a cloud-streaming service."),
        Rule(id: "d3d12-device",
             needles: ["failed to create d3d12", "d3d12createdevice", "vkd3d", "device removed"],
             severity: .caveat,
             title: "D3D12 device creation failed",
             detail: "The game couldn't create a Direct3D 12 device on the current backend.",
             suggestion: "Switch this bottle to the Sikarugir backend (free D3D12 → Metal). DXVK alone only covers D3D9–11."),
        Rule(id: "d3d11-device",
             needles: ["failed to create d3d11", "d3d11createdevice", "dxgi_error"],
             severity: .caveat,
             title: "D3D11 device creation failed",
             detail: "Direct3D 11 init failed — usually a backend that can't reach the GPU (wined3d's GL on Apple Silicon).",
             suggestion: "Switch to DXMT or Sikarugir for a Metal-backed D3D11 path."),
        Rule(id: "avx-int3",
             needles: ["illegal instruction", "int3", "0x80000003"],
             severity: .caveat,
             title: "CPU fault at startup (int3 / illegal instruction)",
             detail: "Often a CPU-feature gate (AVX) or an anti-tamper fail-fast. Fable already advertises AVX via ROSETTA_ADVERTISE_AVX.",
             suggestion: "If it persists across backends, the exe's protector likely rejects emulation — not fixable from Fable. A clean (un-repacked) copy may work."),
        Rule(id: "missing-dll",
             needles: ["err:module:import_dll", "library not found", "dll not found"],
             severity: .caveat,
             title: "A dependency DLL is missing",
             detail: "Wine couldn't resolve a DLL the game imports.",
             suggestion: "Check the line for the DLL name and install the matching dependency (often a redist or winetricks verb)."),
        Rule(id: "directx",
             needles: ["d3dx9", "d3dx11", "xinput1_3", "x3daudio"],
             severity: .caveat,
             title: "Legacy DirectX redistributable missing",
             detail: "The game needs the old DirectX redistributable DLLs (d3dx9, xinput, etc.).",
             suggestion: "Install the DirectX runtime (June 2010) from the bottle's Dependencies."),

        // ——— Signatures from the 2026-06 investigations (docs/ARCHITECTURE.md) ———

        Rule(id: "d3dmetal-dlopen",
             needles: ["failed to dlopen d3dmetal", "gfxthandle"],
             severity: .caveat,
             title: "D3DMetal framework not found",
             detail: "The renderer's dispatch library couldn't load Apple's D3DMetal.framework — no Metal surface, so the game window stays black or the game exits.",
             suggestion: "Re-run the D3DMetal step in Settings → About → onboarding, or update the Sikarugir component. Fable sets the framework path automatically on the Sikarugir backend."),
        Rule(id: "abi-mismatch",
             needles: ["c0000142"],
             severity: .caveat,
             title: "DLL initialization failed (c0000142)",
             detail: "A module refused to initialize before the game reached main() — the classic sign of renderer files built for a different Wine (mismatched dispatch ABI).",
             suggestion: "Switch this bottle to the Sikarugir backend (its Wine and renderer are a matched pair), or reinstall the backend's component so the pieces match."),
        Rule(id: "quarantine",
             needles: ["library load disallowed by system policy", "code signature invalid", "no cdhash"],
             severity: .caveat,
             title: "macOS blocked a library (quarantine)",
             detail: "A dylib carries the quarantine flag, so Rosetta refused to load it — components downloaded by a browser get this.",
             suggestion: "Reinstall the component through Fable (it clears quarantine automatically). For manual copies: xattr -dr com.apple.quarantine <path>."),
        Rule(id: "freetype",
             needles: ["wine cannot find the freetype font library"],
             severity: .caveat,
             title: "FreeType missing — text will be blank",
             detail: "Wine's DirectWrite has no font rasterizer, so windows render with no text at all (buttons and labels appear empty).",
             suggestion: "Relaunch the game from Fable — it re-stages the engine's font libraries on launch. If it persists, reinstall the Sikarugir component."),
        Rule(id: "gnutls",
             needles: ["failed to load libgnutls", "gnutls_initialize failed", "err:secur32"],
             severity: .caveat,
             title: "TLS libraries missing — HTTPS is dead",
             detail: "Wine couldn't load GnuTLS, so anything needing HTTPS fails: Steam's login QR, launcher sign-ins, in-game stores.",
             suggestion: "Relaunch from Fable (it re-stages the engine's TLS libraries). If it persists, reinstall the Sikarugir component."),
        Rule(id: "steamservice",
             needles: ["failed to create service pipe", "bopenservice failed", "failed to load steam service"],
             severity: .caveat,
             title: "Steam's service can't start (WoW64 limit)",
             detail: "Steam's 32-bit helper service can't talk across the 64-bit boundary on this Wine build — downloads finish but installs stall at “installing files”.",
             suggestion: "Use “Finish Stuck Steam Downloads” on the bottle page (Fable also runs it automatically when you open the bottle)."),
        Rule(id: "gpu-hang",
             needles: ["execution of the command buffer was aborted", "iogpucommandqueue", "gpu restart"],
             severity: .caveat,
             title: "GPU command buffer aborted (overload)",
             detail: "Metal killed a command buffer — usually sustained GPU + unified-memory pressure during long sessions.",
             suggestion: "Apply Rock Solid on the bottle (60 fps cap + MetalFX), and lower texture quality in-game. On 16–24 GB machines close other heavy apps."),
        Rule(id: "out-of-memory",
             needles: ["e_outofmemory", "0x8007000e", "not enough memory resources"],
             severity: .caveat,
             title: "Out of memory",
             detail: "The game exhausted memory — on Apple Silicon, RAM and VRAM are the same unified pool, so big textures squeeze everything.",
             suggestion: "Lower texture/shadow quality, cap the frame rate, and close other apps. MetalFX (render lower, upscale) directly reduces memory pressure."),
        Rule(id: "denuvo",
             needles: ["denuvo"],
             severity: .knownBlocker,
             title: "Denuvo anti-tamper detected",
             detail: "Denuvo-protected builds frequently refuse to run under Wine/Rosetta — and when they fail, they fail identically on every backend.",
             suggestion: "If it crashes the same way on two backends, stop switching backends — it's the protector. Play via PC streaming, or wait for a build without Denuvo."),
        Rule(id: "xaudio",
             needles: ["xaudio2_", "xactengine"],
             severity: .caveat,
             title: "XAudio (game audio) DLLs missing",
             detail: "The game uses XAudio2 for sound and the redistributable isn't in the bottle — typical symptom: crash at launch or no audio.",
             suggestion: "Install the DirectX runtime or the `faudio` winetricks verb from the bottle's Dependencies."),
        Rule(id: "wineserver-mismatch",
             needles: ["your wineserver binary was not upgraded correctly", "wine client error:0: version mismatch"],
             severity: .caveat,
             title: "Two Wine versions collided in this bottle",
             detail: "A wineserver from a different Wine build — usually the Sikarugir backend's, left running by Steam or a game — still owned the prefix when another Wine tried to use it. Installs and tools fail with a protocol 'version mismatch' until it exits.",
             suggestion: "Quit Steam and any running games in this bottle (or Force Kill Wine Processes on the bottle page), wait a few seconds, then retry."),
        Rule(id: "dotnet-modern",
             needles: ["failed to resolve hostfxr.dll", "you must install .net to run this application"],
             severity: .caveat,
             title: "Needs a modern .NET runtime (6/7/8)",
             detail: "The app is a .NET (Core) application and the matching runtime isn't in the bottle — the log's 'App host version' line names the major version it wants.",
             suggestion: "Install the matching .NET Desktop Runtime (x64) with Microsoft's official installer via the bottle's Run Installer — winetricks only carries verbs up to .NET 7. Make sure nothing is running in the bottle first."),
        Rule(id: "coreclr-dotnet-host",
             needles: ["failed to create coreclr", "failed to load system.private.corelib"],
             severity: .caveat,
             title: "Modern .NET (8+) runtime can't start on this backend",
             detail: "A .NET 8+ app loaded its runtime but Wine couldn't create the CoreCLR host. Older Wine builds — including GPTK's — can't host current .NET's CLR; a newer Wine can. (The app usually exits within seconds of launch.)",
             suggestion: "Switch this bottle to the Sikarugir backend (newer Wine) for .NET 8+ apps — the GPTK/older-Wine path can't create the CLR. A self-contained .NET app needs no runtime install once the Wine base is new enough."),
        Rule(id: "avalonia-no-surface",
             needles: ["unable to initialize winui compositor", "createdispatcherqueuecontroller"],
             severity: .knownBlocker,
             title: "Avalonia UI app can't create a window",
             detail: "An Avalonia (.NET) app started but couldn't get a renderable window surface — Wine's Mac driver has no WinUI compositor and MoltenVK exposes no win32 Vulkan surface — so it exits within a few seconds showing nothing. This is a class limitation, not a per-app bug.",
             suggestion: "Avalonia desktop apps don't render under macOS Wine yet (a Wine/MoltenVK win32-surface gap). If the app is just a front-end for a background service or a downloadable payload, use that part directly; the GUI itself is a known wall until Wine gains a win32 Vulkan surface path."),
        Rule(id: "mono-ipc-singleinstance",
             needles: ["ipcserverchannel", "must have a structlayout attribute", "singleinstance"],
             severity: .knownBlocker,
             title: "Launcher hits a Wine Mono IPC bug",
             detail: "A .NET launcher's single-instance check (Microsoft.Shell.SingleInstance → .NET Remoting IpcServerChannel) throws MarshalDirectiveException on Wine Mono, which doesn't fully implement that channel. The real Microsoft .NET Framework handles it — but that won't install under Wine. Seen with Battlestate's Escape from Tarkov launcher, 2026-07-09.",
             suggestion: "Wine Mono can't run this launcher and the real .NET Framework can't be installed on this stack. If you only need the launcher to fetch game files, get them from a Windows machine/VM and copy them into the bottle, then launch the game (or its offline/mod launcher) directly."),
        Rule(id: "wpf-culture-4096",
             needles: ["culturenotfoundexception", "4096 (0x1000) is an invalid culture", "invalid culture identifier"],
             severity: .caveat,
             title: "WPF crashed on the keyboard layout (culture 4096)",
             detail: "A .NET/WPF app queried the keyboard input language and Wine returned 0x1000 — the placeholder it uses when your Mac's locale has no standard Windows equivalent (common outside US English). WPF then throws CultureNotFoundException before the window shows.",
             suggestion: "Fable repairs this automatically on the next launch from a cold bottle (it resets the prefix keyboard layout to US). If it persists, quit everything in the bottle and relaunch."),
        Rule(id: "unity-graphics-init",
             needles: ["initializeenginegraphics failed", "failed to initialize player", "failed to initialize graphics"],
             severity: .caveat,
             title: "Engine couldn't initialize graphics",
             detail: "A Unity/engine title couldn't create its graphics device on this backend. Some engines white-screen on D3DMetal (audio and input work, nothing renders) or refuse to start on DXMT.",
             suggestion: "Try a different backend for this game — for Unity titles, DXMT or built-in Wine often render where D3DMetal white-screens, and vice-versa. If every backend white-screens, it's a D3DMetal present bug (stream it or use CrossOver)."),
        Rule(id: "physx",
             needles: ["physxloader", "physx3", "apex_"],
             severity: .caveat,
             title: "NVIDIA PhysX runtime missing",
             detail: "The game links PhysX and its redistributable was never installed (Steam usually runs it via _CommonRedist).",
             suggestion: "Run “Install Dependencies” on the game, or the `physx` winetricks verb."),
    ]

    // MARK: Cross-backend crash correlation (the First Light rule)

    /// Classifies an abnormal exit into a comparable crash signature, or nil
    /// when the crash isn't in the anti-tamper/CPU-gate class worth
    /// correlating. Deliberately narrow: only the deliberate-breakpoint
    /// family, which is what protectors and Rosetta CPU gates produce — the
    /// crashes that look identical no matter which backend runs the game.
    static func crashSignature(exitCode: Int32, logTail: String) -> String? {
        let haystack = logTail.lowercased()
        let breakpointTells = ["int3", "0x80000003", "exception_breakpoint", "illegal instruction"]
        if breakpointTells.contains(where: { haystack.contains($0) }) {
            return "int3"
        }
        return nil
    }

    /// The verdict when the same signature shows up on two different
    /// backends: it's the game rejecting the environment, not a backend
    /// problem — switching further is wasted evenings. Documented in
    /// docs/ARCHITECTURE.md ("the First Light rule"); validated the hard way
    /// (GPTK, DXVK, Sikarugir, AND CrossOver all hit the identical int3).
    static func crossBackendFinding(signature: String, backends: [String]) -> CompatibilityFinding {
        CompatibilityFinding(
            id: "doctor-cross-backend",
            severity: .knownBlocker,
            title: "Same crash on \(backends.count) different backends",
            detail: "This game hit the identical failure (\(signature)) on \(backends.joined(separator: " and ")). When a crash doesn't change with the graphics backend, it's the game itself checking its environment (anti-tamper, or a CPU gate under Rosetta) — no backend switch will fix it.",
            suggestion: "Stop switching backends. If you own a Windows PC that runs it, stream it (Moonlight/Sunshine/Steam Link); otherwise a cloud service. A clean, un-repacked copy is occasionally the difference."
        )
    }

    /// DLL names Wine failed to import, parsed from the log
    /// (`err:module:import_dll Library FOO.dll … not found`). Order of first
    /// appearance, deduplicated case-insensitively.
    static func missingDLLs(in log: String) -> [String] {
        let pattern = /import_dll\s+Library\s+(\S+\.dll)/.ignoresCase()
        var seen = Set<String>()
        var names: [String] = []
        for match in log.matches(of: pattern) {
            let name = String(match.1)
            if seen.insert(name.lowercased()).inserted { names.append(name) }
        }
        return names
    }

    /// Diagnoses raw log text. Empty result = no known problems matched.
    static func diagnose(log: String) -> [CompatibilityFinding] {
        let haystack = log.lowercased()
        return rules
            .filter { rule in rule.needles.contains { haystack.contains($0) } }
            .map { rule in
                var detail = rule.detail
                // Name the culprit instead of telling the user to go read
                // the log themselves.
                if rule.id == "missing-dll" {
                    let dlls = missingDLLs(in: log)
                    if !dlls.isEmpty {
                        detail = "Wine couldn't resolve: \(dlls.joined(separator: ", "))."
                    }
                }
                return CompatibilityFinding(
                    id: "doctor-\(rule.id)", severity: rule.severity,
                    title: rule.title, detail: detail, suggestion: rule.suggestion
                )
            }
    }

    /// Reads a log file (best-effort) and diagnoses it.
    static func diagnose(logFile url: URL) -> [CompatibilityFinding] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return diagnose(log: text)
    }
}
