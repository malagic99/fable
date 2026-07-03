import Foundation

/// Resolves a game's Steam appid from the bottle's `appmanifest_*.acf` files,
/// so ProtonDB (keyed by appid) can be looked up.
///
/// We read the two fields we need (`installdir`, `appid`) with a small regex
/// rather than the full VDF parser — the manifest is a flat key/value list, and
/// referencing the `indirect enum`-based parser from here tripped a Swift
/// type-checker cycle. The regex is narrower and side-steps it cleanly.
enum SteamAppManifest {

    /// The install-directory name from a Steam game's exe path — the component
    /// right after `steamapps/common/`. nil for non-Steam paths.
    static func installDir(fromExecutablePath path: String) -> String? {
        let parts = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init)
        guard let i = parts.firstIndex(where: { $0.caseInsensitiveCompare("common") == .orderedSame }),
              parts.indices.contains(i - 1),
              parts[i - 1].caseInsensitiveCompare("steamapps") == .orderedSame,
              parts.indices.contains(i + 1) else { return nil }
        return parts[i + 1]
    }

    /// The appid whose `appmanifest_<id>.acf` declares the given install dir.
    static func appID(forInstallDir dirName: String, steamRoot: URL) -> Int? {
        let steamapps = steamRoot.appending(path: "steamapps", directoryHint: .isDirectory)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: steamapps, includingPropertiesForKeys: nil
        ) else { return nil }

        for acf in entries where acf.lastPathComponent.hasPrefix("appmanifest_")
            && acf.pathExtension == "acf" {
            guard let text = try? String(contentsOf: acf, encoding: .utf8),
                  let manifestDir = value(of: "installdir", in: text),
                  manifestDir.caseInsensitiveCompare(dirName) == .orderedSame,
                  let resolved = value(of: "appid", in: text).flatMap(Int.init) else { continue }
            return resolved
        }
        return nil
    }

    /// Convenience: resolve a game's appid from its exe path + the bottle's
    /// Steam root. nil when it isn't a Steam game or no manifest matches.
    static func appID(forExecutablePath path: String, steamRoot: URL) -> Int? {
        guard let dirName = installDir(fromExecutablePath: path) else { return nil }
        return appID(forInstallDir: dirName, steamRoot: steamRoot)
    }

    /// Every installed app in a Steam library (works on the native macOS
    /// client's `~/Library/Application Support/Steam` too): appid + display
    /// name per `appmanifest_*.acf`. Steam's own tooling entries (redists,
    /// SteamVR, …) are left in — the import UI lets the user choose.
    static func installedApps(steamRoot: URL) -> [(appID: Int, name: String, installDir: String?)] {
        let steamapps = steamRoot.appending(path: "steamapps", directoryHint: .isDirectory)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: steamapps, includingPropertiesForKeys: nil
        ) else { return [] }

        var apps: [(appID: Int, name: String, installDir: String?)] = []
        for acf in entries where acf.lastPathComponent.hasPrefix("appmanifest_")
            && acf.pathExtension == "acf" {
            guard let text = try? String(contentsOf: acf, encoding: .utf8),
                  let appID = value(of: "appid", in: text).flatMap(Int.init),
                  let name = value(of: "name", in: text), !name.isEmpty
            else { continue }
            apps.append((appID, name, value(of: "installdir", in: text)))
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Whether a manifest's game files genuinely exist on disk. A stale
    /// `appmanifest_*.acf` can claim "installed" (with a large SizeOnDisk)
    /// while `common/<installdir>` holds nothing but a .DS_Store — Steam then
    /// fails the launch silently, so such entries must not be offered for
    /// import. The walk early-outs once `threshold` bytes are seen, so a real
    /// install costs a handful of stat calls.
    static func hasGameFiles(installDir: String?, steamRoot: URL, threshold: Int64 = 5_000_000) -> Bool {
        guard let installDir, !installDir.isEmpty else { return false }
        let dir = steamRoot.appending(path: "steamapps/common", directoryHint: .isDirectory)
            .appending(path: installDir, directoryHint: .isDirectory)
        guard let enumerator = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return false }
        var seen: Int64 = 0
        for case let file as URL in enumerator {
            seen += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            if seen >= threshold { return true }
        }
        return false
    }

    /// The native macOS Steam client's root, when present.
    static func nativeSteamRoot(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        let root = home.appending(path: "Library/Application Support/Steam", directoryHint: .isDirectory)
        let steamapps = root.appending(path: "steamapps", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: steamapps.path) ? root : nil
    }

    /// Extracts the quoted value following a quoted `key` on a VDF line:
    /// `"installdir"    "DEATHLOOP"` → `DEATHLOOP`.
    static func value(of key: String, in text: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        guard let regex = try? NSRegularExpression(
            pattern: "\"\(escaped)\"\\s*\"([^\"]*)\"", options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[valueRange])
    }
}
