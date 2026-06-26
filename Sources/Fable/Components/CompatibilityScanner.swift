import Foundation

/// Walks a game's install directory and flags compatibility concerns:
/// NVIDIA Streamline, DirectStorage, kernel anti-cheats, Goldberg
/// Steam emulator misconfigurations, repack indicators. Pure
/// filesystem inspection — no execution, no PE parsing yet.
///
/// Why now: real-world test on 2026-06-14 ran 007 First Light through
/// every backend permutation before discovering the install had
/// Streamline plugins + Goldberg without steam_interfaces.txt — both
/// detectable in seconds without launching anything.
enum CompatibilityScanner {
    /// Scan a game's directory (one or more levels deep) and return
    /// every applicable Finding. Safe to call on directories that
    /// don't exist (returns empty).
    static func scan(gameDirectory: URL) -> [CompatibilityFinding] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: gameDirectory.path) else { return [] }

        let inventory = collectFiles(at: gameDirectory)
        var findings: [CompatibilityFinding] = []

        // Each rule is its own small function. Adding a marker is a
        // one-rule change and trivially testable.
        findings += streamlineFindings(inventory: inventory)
        findings += directStorageFindings(inventory: inventory)
        findings += antiCheatFindings(inventory: inventory)
        findings += goldbergFindings(inventory: inventory, gameDirectory: gameDirectory)
        findings += repackFindings(inventory: inventory, gameDirectory: gameDirectory)
        findings += denuvoFindings(inventory: inventory)

        return findings
    }

    /// Recommends a graphics backend based on a Findings set. Returns
    /// nil when the install hits a hard blocker (anti-cheat) — no
    /// configuration will help.
    ///
    /// The decision tree mirrors the doc-comment backend matrix on
    /// GraphicsBackend itself. Crossover wins when present because
    /// it's the highest-compatibility path; otherwise we prefer DXVK
    /// for Streamline-bearing games (modern SEH) and GPTK when none
    /// of the SEH-killer markers are present.
    static func recommendedBackend(
        for findings: [CompatibilityFinding],
        crossOverAvailable: Bool,
        sikarugirAvailable: Bool = false
    ) -> GraphicsBackend? {
        // Hard blockers: no path forward.
        if findings.contains(where: { $0.severity == .knownBlocker }) {
            return nil
        }

        let ids = Set(findings.map(\.id))
        let hasStreamline = ids.contains("streamline")
        let hasDirectStorage = ids.contains("directstorage")
        let hasDenuvo = ids.contains("denuvo-heuristic")
        let needsModernD3D12 = hasStreamline || hasDirectStorage || hasDenuvo

        // Sikarugir is the best path for modern D3D12: free, modern-wine
        // SEH + real D3DMetal (the matched pair GPTK lacks). Prefer it
        // over CrossOver when both are present — same capability, no cost.
        if needsModernD3D12 {
            if sikarugirAvailable { return .sikarugir }
            if crossOverAvailable { return .crossover }
            // Neither modern-D3DMetal stack present → DXVK on modern Wine.
            // Loses D3DMetal but at least has modern SEH. (D3D11 only —
            // a D3D12 game still won't render, but the recommendation
            // surfaces the "install Sikarugir/CrossOver" path via the UI.)
            return .dxvk
        }

        // Clean install, no concerning markers. Prefer the free flagship
        // (Sikarugir: modern Wine + D3DMetal, handles D3D9–12) when it's
        // installed; GPTK (Wine 7.7) is the legacy fallback. The picker takes
        // over if the user disagrees.
        if sikarugirAvailable { return .sikarugir }
        if crossOverAvailable { return .crossover }
        return .gptk
    }

    // MARK: Inventory

    /// Lowercased relative paths of every file under root, capped at
    /// `maxFiles` to keep scans cheap on large installs.
    nonisolated static func collectFiles(at root: URL, maxFiles: Int = 20_000) -> Set<String> {
        let fm = FileManager.default
        // Normalize symlinks — macOS temporaryDirectory is /var/...
        // but resolves to /private/var/...; enumerator emits the
        // resolved form, so we have to compare them in the same shape.
        let normalizedRoot = root.standardizedFileURL.resolvingSymlinksInPath().path
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var collected: Set<String> = []
        for case let url as URL in enumerator {
            if collected.count >= maxFiles { break }
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isFile else { continue }
            let abs = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard abs.hasPrefix(normalizedRoot) else { continue }
            let relative = String(abs.dropFirst(normalizedRoot.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .lowercased()
            collected.insert(relative)
        }
        return collected
    }

    // MARK: Rules

    nonisolated private static func streamlineFindings(inventory: Set<String>) -> [CompatibilityFinding] {
        let streamlineLeafs = inventory.filter {
            let leaf = ($0 as NSString).lastPathComponent
            return leaf.hasPrefix("sl.") && leaf.hasSuffix(".dll")
        }
        guard !streamlineLeafs.isEmpty else { return [] }
        return [CompatibilityFinding(
            id: "streamline",
            severity: .caveat,
            title: "NVIDIA Streamline detected",
            detail: "Found \(streamlineLeafs.count) sl.*.dll plugin(s). Streamline drives DLSS, Reflex, and PCL. On Apple Silicon the plugins may fail to validate and throw a C++ exception during init; Wine 7.7 (GPTK) can't unwind it cleanly. Wine 11+ usually does.",
            suggestion: "If the game crashes with int3 right after startup, switch backend from GPTK to Off (Wine built-in) so wine-devel-11.10's SEH handles the unwind."
        )]
    }

    nonisolated private static func directStorageFindings(inventory: Set<String>) -> [CompatibilityFinding] {
        let hasDStorage = inventory.contains { $0.hasSuffix("/dstorage.dll") || $0 == "dstorage.dll" }
        let hasDStorageCore = inventory.contains { $0.hasSuffix("/dstoragecore.dll") || $0 == "dstoragecore.dll" }
        guard hasDStorage || hasDStorageCore else { return [] }
        return [CompatibilityFinding(
            id: "directstorage",
            severity: .caveat,
            title: "DirectStorage required",
            detail: "Game ships DStorage. GPU decompression isn't available on macOS Wine; the CPU fallback works for most titles but adds load-time overhead.",
            suggestion: "Usually fine. If asset streaming hangs, try `WINEDLLOVERRIDES=dstorage,dstoragecore=` in the game's per-game environment to force-disable."
        )]
    }

    nonisolated private static func antiCheatFindings(inventory: Set<String>) -> [CompatibilityFinding] {
        var hits: [(label: String, file: String)] = []
        for path in inventory {
            let leaf = ((path as NSString).lastPathComponent).lowercased()
            // EAC: install dir is usually EasyAntiCheat/; key binaries
            // are easyanticheat_x64.dll, easyanticheat_setup.exe, EACLauncher.exe.
            if leaf.hasPrefix("easyanticheat") ||
               leaf == "eac.dll" ||
               leaf == "eaclauncher.exe" ||
               path.contains("easyanticheat/") {
                hits.append(("Easy Anti-Cheat", path))
            }
            // BattlEye: install dir is BattlEye/; binaries BEService.exe,
            // BEDaisy.sys, BattlEyeLauncher.exe.
            else if leaf.hasPrefix("battleye") ||
                    leaf == "beservice.exe" ||
                    leaf == "be_service.exe" ||
                    leaf == "bedaisy.sys" ||
                    path.contains("battleye/") {
                hits.append(("BattlEye", path))
            }
            // Vanguard: vgc.exe is the user-mode service.
            else if leaf == "vgc.exe" || leaf.contains("vanguard") {
                hits.append(("Riot Vanguard", path))
            }
        }
        return Array(Set(hits.map(\.label))).sorted().map { label in
            CompatibilityFinding(
                id: "anticheat-\(label.lowercased().replacingOccurrences(of: " ", with: "-"))",
                severity: .knownBlocker,
                title: "\(label) anti-cheat detected",
                detail: "\(label) requires kernel-level access on Windows. There is no working Wine implementation; the game will fail at startup or get banned for tampering.",
                suggestion: "This game cannot run on macOS Wine today. Consider GeForce Now or another cloud streaming service."
            )
        }
    }

    nonisolated private static func goldbergFindings(
        inventory: Set<String>,
        gameDirectory: URL
    ) -> [CompatibilityFinding] {
        // Goldberg's fingerprint: steam_settings/configs.*.ini or
        // steam_settings/steam_appid.txt without the real Valve dll.
        let hasGoldbergConfig = inventory.contains {
            $0.contains("steam_settings/") || $0.contains("steam_settings\\")
        }
        guard hasGoldbergConfig else { return [] }
        let hasInterfaces = inventory.contains {
            $0.hasSuffix("steam_settings/steam_interfaces.txt") ||
            $0.hasSuffix("steam_settings\\steam_interfaces.txt")
        }
        var findings: [CompatibilityFinding] = [
            CompatibilityFinding(
                id: "goldberg-emu",
                severity: .info,
                title: "Goldberg Steam Emulator detected",
                detail: "This game uses Goldberg's emulator instead of the real Steam client. Most games work; some assert if Steam interface versions don't match what they expect.",
                suggestion: ""
            )
        ]
        if !hasInterfaces {
            findings.append(CompatibilityFinding(
                id: "goldberg-no-interfaces",
                severity: .caveat,
                title: "Goldberg is missing steam_interfaces.txt",
                detail: "Without this file, Goldberg hands back broken Steam API interface pointers. Modern games (Steamworks SDK 1.55+) often int3 after init because of this.",
                suggestion: "Generate steam_interfaces.txt by running Goldberg's generate_interfaces tool against the original Valve steam_api64.dll, then drop it next to the existing configs.*.ini."
            ))
        }
        return findings
    }

    nonisolated private static func repackFindings(
        inventory: Set<String>,
        gameDirectory: URL
    ) -> [CompatibilityFinding] {
        // Common repack signatures inside the install path
        let path = gameDirectory.path.lowercased()
        let repackTokens = ["fitgirl", "dodi", "elamigos", "voices38", "skidrow", "codex", "razor1911"]
        guard repackTokens.contains(where: { path.contains($0) }) else { return [] }
        return [CompatibilityFinding(
            id: "repack-install",
            severity: .info,
            title: "Repacked / community install detected",
            detail: "The install path contains a known repacker tag. Repacks sometimes modify game executables or skip dependencies; if behavior looks weird, the legit install path is the cleaner baseline.",
            suggestion: ""
        )]
    }

    nonisolated private static func denuvoFindings(inventory: Set<String>) -> [CompatibilityFinding] {
        // Denuvo doesn't ship visible DLLs but leaves traces in the
        // exe's import table and section names. For Day 1 we keep the
        // rule heuristic: a `core.exe` next to the main exe alongside
        // VMP/Themida-style markers. Conservative — false-negatives
        // ok, false-positives not.
        let suspicious = inventory.filter {
            let leaf = ($0 as NSString).lastPathComponent
            return leaf == "core.exe"
        }
        guard !suspicious.isEmpty else { return [] }
        return [CompatibilityFinding(
            id: "denuvo-heuristic",
            severity: .caveat,
            title: "Possible Denuvo / anti-tamper layer",
            detail: "Detected a `core.exe` companion next to the main executable — a common Denuvo/VMProtect signature. Denuvo works in many cases on macOS Wine but can be slow on first launch (hours of compilation) and occasionally hits Wine timer/scheduler edge cases.",
            suggestion: "If startup hangs for very long, leave it for 15–30 minutes once before declaring it broken — first-launch JIT is normal."
        )]
    }
}
