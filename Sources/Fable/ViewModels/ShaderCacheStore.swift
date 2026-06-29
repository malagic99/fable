import Foundation

/// Manages D3DMetal shader caches: keeps a durable per-machine snapshot so a
/// macOS purge of the volatile darwin cache can't wipe your warmed shaders, and
/// offloads that snapshot to external storage to reclaim local space.
///
/// Auto behavior (wired in the app): snapshot after a game session, and restore
/// the snapshot at startup if the live cache was purged. Manual behavior (in
/// Settings): offload to / bring back from an external drive.
///
/// All heavy file work runs off the main actor; published state updates on it.
@MainActor
final class ShaderCacheStore: ObservableObject {
    @Published private(set) var localBytes: Int64 = 0
    @Published private(set) var liveBytes: Int64 = 0
    @Published private(set) var externalLocation: URL?
    @Published private(set) var isWorking = false

    /// Durable local snapshot: `…/ShaderCache/snapshot/<bundle-id>/…`.
    private let snapshotDir: URL
    /// Records where the snapshot was offloaded (a bookmark-free plain path).
    private let markerFile: URL

    init(root: URL = AppPaths.shaderCache) {
        snapshotDir = root.appending(path: "snapshot", directoryHint: .isDirectory)
        markerFile = root.appending(path: "external-location.txt")
        externalLocation = Self.readMarker(markerFile)
        Task { await refresh() }
    }

    /// Recompute sizes (live darwin caches + local snapshot).
    func refresh() async {
        let snapshot = snapshotDir
        let (local, live) = await Task.detached(priority: .utility) { () -> (Int64, Int64) in
            let snap = (try? FileManager.default.contentsOfDirectory(
                at: snapshot, includingPropertiesForKeys: nil
            )) ?? []
            let localSize = ShaderCache.totalSize(of: snap)
            let liveSize = ShaderCache.totalSize(of: ShaderCache.wineMetalCaches(in: ShaderCache.darwinCacheRoot()))
            return (localSize, liveSize)
        }.value
        localBytes = local
        liveBytes = live
    }

    /// Copy the current live wine Metal caches into the durable snapshot
    /// (live is newest, so it wins). Called automatically after a session.
    func snapshot() async {
        let dest = snapshotDir
        await runWork {
            let fm = FileManager.default
            try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
            for cache in ShaderCache.wineMetalCaches(in: ShaderCache.darwinCacheRoot()) {
                let target = dest.appending(path: cache.lastPathComponent, directoryHint: .isDirectory)
                try? fm.removeItem(at: target)
                try? fm.copyItem(at: cache, to: target)
            }
        }
        await refresh()
    }

    /// If the live cache was purged (reboot/cleanup) but we hold a snapshot,
    /// copy it back. Never clobbers a live cache that's still present.
    func restoreLiveIfPurged() async {
        let snapshot = snapshotDir
        await runWork {
            let fm = FileManager.default
            let cacheRoot = ShaderCache.darwinCacheRoot()
            let stored = (try? fm.contentsOfDirectory(at: snapshot, includingPropertiesForKeys: nil)) ?? []
            for entry in stored where ShaderCache.isWineCacheName(entry.lastPathComponent) {
                let live = cacheRoot.appending(path: entry.lastPathComponent, directoryHint: .isDirectory)
                let liveMetal = live.appending(path: "com.apple.metal", directoryHint: .isDirectory)
                guard !fm.fileExists(atPath: liveMetal.path) else { continue }  // still present → leave it
                try? fm.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
                try? fm.copyItem(at: entry, to: live)
            }
        }
        await refresh()
    }

    /// Move the local snapshot to an external folder to reclaim local space.
    func offload(to externalParent: URL) async {
        let dest = externalParent.appending(path: "FableShaderCache", directoryHint: .isDirectory)
        let snapshot = snapshotDir
        let marker = markerFile
        await runWork {
            let fm = FileManager.default
            try? fm.removeItem(at: dest)
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Copy then clear local (copy-then-delete is safer than move across volumes).
            if (try? fm.copyItem(at: snapshot, to: dest)) != nil {
                try? fm.removeItem(at: snapshot)
            }
            try? Data(dest.path.utf8).write(to: marker, options: .atomic)
        }
        externalLocation = Self.readMarker(marker)
        await refresh()
    }

    /// Copy the offloaded snapshot back to local storage (so it can restore to
    /// the live cache). Clears the external marker.
    func bringBack() async {
        guard let external = externalLocation else { return }
        let snapshot = snapshotDir
        let marker = markerFile
        await runWork {
            let fm = FileManager.default
            guard fm.fileExists(atPath: external.path) else { return }
            try? fm.removeItem(at: snapshot)
            try? fm.createDirectory(at: snapshot.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: external, to: snapshot)
            try? fm.removeItem(at: marker)
        }
        externalLocation = nil
        await refresh()
    }

    // MARK: Internals

    private func runWork(_ work: @escaping @Sendable () -> Void) async {
        isWorking = true
        await Task.detached(priority: .utility, operation: work).value
        isWorking = false
    }

    private static func readMarker(_ file: URL) -> URL? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(filePath: path)
    }
}
