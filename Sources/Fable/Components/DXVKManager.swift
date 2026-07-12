import Foundation

/// DXVK + vkd3d-proton routing — the open-source DirectX→Vulkan→
/// MoltenVK→Metal path for modern Wine.
///
/// IMPORTANT: "DXVK" is shorthand here for the full stack. DXVK itself
/// only handles D3D9/10/11 → Vulkan; D3D12 → Vulkan is the SEPARATE
/// vkd3d-proton project. A D3D12 game (e.g. any modern UE5 title)
/// needs vkd3d-proton's d3d12.dll + d3d12core.dll alongside DXVK's
/// dxgi.dll. Both install into the prefix's system32/syswow64.
@MainActor
final class DXVKManager: ObservableObject {
    /// Canary for the install check — DXVK's d3d11.dll is ~4MB whereas
    /// Wine's builtin stub is tiny.
    nonisolated static let canaryDLL = "windows/system32/d3d11.dll"

    /// DLLs the stack provides — forced native so Wine loads the
    /// prefix copies instead of its builtins. d3d12core is vkd3d-proton
    /// 3.x's split-out core (d3d12.dll depends on it).
    nonisolated static let routedDLLs = ["d3d9", "d3d10core", "d3d11", "d3d12", "d3d12core", "dxgi"]

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

    /// The Memory Diet's DXVK face: a prefix-level config file capping the
    /// VRAM DXVK advertises (MoltenVK otherwise reports Metal's ~3/4-of-RAM
    /// working set as *dedicated* VRAM, so games budget toward memory the
    /// unified pool can't actually spare). `DXVK_CONFIG_FILE` works on every
    /// DXVK we route, unlike the 2.1+ `DXVK_CONFIG` var.
    nonisolated static let memoryDietConfigName = "fable-dxvk.conf"

    /// Writes (or refreshes) the hardware-sized config into the prefix and
    /// returns its URL. Skips the write when content already matches.
    nonisolated static func ensureMemoryDietConfig(at prefix: URL, vramMB: Int) throws -> URL {
        let url = prefix.appending(path: memoryDietConfigName)
        let content = MemoryDiet.dxvkConfig(vramMB: vramMB) + "\n"
        if (try? String(contentsOf: url, encoding: .utf8)) != content {
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    /// Environment fragment routing d3d10core/d3d11/d3d12/dxgi to
    /// native so DXVK's DLLs win over Wine's built-ins. DXVK reads
    /// extra config from `DXVK_*` vars the user can set per-game.
    nonisolated static func launchEnvironment(
        baseOverrides: String,
        frameRateCap: Int?,
        logFile: URL?,
        configFile: URL? = nil
    ) -> [String: String] {
        var env: [String: String] = [:]
        env["WINEDLLOVERRIDES"] = "\(baseOverrides);\(routedDLLs.joined(separator: ","))=n"
        if let frameRateCap, frameRateCap > 0 {
            env["DXVK_FRAME_RATE"] = String(frameRateCap)
        }
        if let logFile {
            env["DXVK_LOG_PATH"] = logFile.deletingLastPathComponent().path
        }
        if let configFile {
            env["DXVK_CONFIG_FILE"] = configFile.path
        }
        return env
    }
}
