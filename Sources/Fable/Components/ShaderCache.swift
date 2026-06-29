import Foundation

/// Locating the on-disk shader caches D3DMetal produces, so Fable can persist
/// and offload them.
///
/// Unlike Proton (a portable per-game `.dxvk-cache` file), D3DMetal's compiled
/// pipelines live in Apple's per-app Metal caches inside the darwin user cache
/// dir (`…/C/<bundle-id>/com.apple.metal`). These survive between sessions —
/// which is why a game smooths out after its first hour — but macOS purges that
/// directory on reboot/cleanup, losing the warmed shaders. We snapshot the
/// wine-attributable ones into stable storage and restore them when the live
/// cache has been purged.
///
/// Deliberately conservative: only touches per-app caches whose bundle id looks
/// wine-derived, NEVER Apple/system caches and NEVER the shared global
/// `com.apple.metal` (which belongs to every Metal app on the Mac).
enum ShaderCache {

    /// The darwin per-user cache dir (`…/C/`) — sibling of the temp dir (`…/T/`).
    static func darwinCacheRoot(fileManager fm: FileManager = .default) -> URL {
        fm.temporaryDirectory
            .deletingLastPathComponent()
            .appending(path: "C", directoryHint: .isDirectory)
    }

    /// True if a cache-dir name belongs to a wine/D3DMetal game (and isn't an
    /// Apple/system cache). The bundle ids D3DMetal creates carry a `wine`/
    /// `wineskin` marker (e.g. `com.Steambuild…Metal….wineskin`).
    static func isWineCacheName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("wine") && !lower.hasPrefix("com.apple.")
    }

    /// Per-app Metal shader caches attributable to wine/D3DMetal games — each a
    /// `<bundle-id>` dir containing a `com.apple.metal` subfolder.
    static func wineMetalCaches(in cacheRoot: URL, fileManager fm: FileManager = .default) -> [URL] {
        guard let entries = try? fm.contentsOfDirectory(
            at: cacheRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.filter { dir in
            guard isWineCacheName(dir.lastPathComponent) else { return false }
            let metal = dir.appending(path: "com.apple.metal", directoryHint: .isDirectory)
            return fm.fileExists(atPath: metal.path)
        }
    }

    /// Total bytes across a set of directories.
    static func totalSize(of dirs: [URL], fileManager fm: FileManager = .default) -> Int64 {
        dirs.reduce(0) { $0 + directorySize(at: $1, fileManager: fm) }
    }

    static func directorySize(at url: URL, fileManager fm: FileManager = .default) -> Int64 {
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
