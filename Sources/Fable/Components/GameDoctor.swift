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
             title: "Needs the .NET runtime",
             detail: "The game tried to load the .NET CLR, which isn't present in the bottle.",
             suggestion: "Install .NET via the bottle's winetricks (e.g. dotnet48) from the Dependencies section."),
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
    ]

    /// Diagnoses raw log text. Empty result = no known problems matched.
    static func diagnose(log: String) -> [CompatibilityFinding] {
        let haystack = log.lowercased()
        return rules
            .filter { rule in rule.needles.contains { haystack.contains($0) } }
            .map {
                CompatibilityFinding(
                    id: "doctor-\($0.id)", severity: $0.severity,
                    title: $0.title, detail: $0.detail, suggestion: $0.suggestion
                )
            }
    }

    /// Reads a log file (best-effort) and diagnoses it.
    static func diagnose(logFile url: URL) -> [CompatibilityFinding] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return diagnose(log: text)
    }
}
