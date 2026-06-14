import Foundation

/// DXVK routing — the open-source D3D11/12→Vulkan→MoltenVK→Metal path
/// for modern Wine. Unlike DXMT and GPTK, DXVK installs via the
/// existing `winetricks dxvk` verb rather than as a Fable-managed
/// component, so this Manager is thin: it just provides the launch
/// env and a presence check.
@MainActor
final class DXVKManager: ObservableObject {
    /// `winetricks dxvk` writes these to the prefix's `system32`/`syswow64`.
    /// `isInstalled(in:)` looks for the 64-bit `d3d11.dll` as the canary.
    nonisolated static let canaryDLL = "windows/system32/d3d11.dll"

    /// DLLs DXVK provides — these go native so Wine loads DXVK's copies
    /// (in system32) instead of Wine's own built-in d3d.
    nonisolated static let routedDLLs = ["d3d10core", "d3d11", "d3d12", "dxgi"]

    /// Whether DXVK is set up for the given bottle. The check is just
    /// the presence of the d3d11.dll — `winetricks dxvk` writes large
    /// (~5MB) DLLs there, whereas a vanilla Wine prefix has none.
    func isInstalled(in bottle: Bottle, bottleManager: BottleManager) -> Bool {
        let d3d11 = bottleManager.driveCDirectory(for: bottle)
            .appending(path: Self.canaryDLL)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: d3d11.path),
              let size = attrs[.size] as? UInt64 else { return false }
        // DXVK's d3d11.dll is ~4MB; Wine's stubs are tiny. 256KB
        // discriminates safely.
        return size > 256 * 1024
    }

    /// Environment fragment routing d3d10core/d3d11/d3d12/dxgi to
    /// native so DXVK's DLLs win over Wine's built-ins. DXVK reads
    /// extra config from `DXVK_*` vars the user can set per-game.
    nonisolated static func launchEnvironment(
        baseOverrides: String,
        frameRateCap: Int?,
        logFile: URL?
    ) -> [String: String] {
        var env: [String: String] = [:]
        env["WINEDLLOVERRIDES"] = "\(baseOverrides);\(routedDLLs.joined(separator: ","))=n"
        if let frameRateCap, frameRateCap > 0 {
            env["DXVK_FRAME_RATE"] = String(frameRateCap)
        }
        if let logFile {
            env["DXVK_LOG_PATH"] = logFile.deletingLastPathComponent().path
        }
        return env
    }
}
