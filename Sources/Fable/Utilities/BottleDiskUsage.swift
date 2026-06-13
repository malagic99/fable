import Foundation

/// Recursive byte count of a bottle's prefix + temp-file cleanup,
/// shared between BottleCard and BottleDetailView.
enum BottleDiskUsage {
    /// Recursively sums allocated sizes under `root`. Cancellable —
    /// honors Task.checkCancellation between entries.
    static func size(of root: URL) throws -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return 0 }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey]
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: keys)
            if values.isRegularFile == true,
               let size = values.totalFileAllocatedSize {
                total &+= Int64(size)
            }
        }
        return total
    }

    /// Default temp paths Wine writes to inside a prefix. Empty
    /// directories are kept (Wine expects them to exist).
    static func tempPaths(in prefix: URL) -> [URL] {
        var paths: [URL] = []
        let driveC = prefix.appending(path: "drive_c", directoryHint: .isDirectory)
        paths.append(driveC.appending(path: "windows/Temp", directoryHint: .isDirectory))
        let users = driveC.appending(path: "users", directoryHint: .isDirectory)
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: users,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) {
            for user in entries {
                paths.append(user.appending(
                    path: "Temp", directoryHint: .isDirectory
                ))
                paths.append(user.appending(
                    path: "AppData/Local/Temp", directoryHint: .isDirectory
                ))
            }
        }
        return paths
    }

    /// Deletes the contents of each `tempPaths(in:)` directory (the
    /// directories themselves remain). Returns bytes freed. Failures on
    /// individual files are swallowed — we want best-effort cleanup,
    /// not a half-done abort.
    @discardableResult
    static func cleanTempFiles(in prefix: URL) throws -> Int64 {
        var freed: Int64 = 0
        let fm = FileManager.default
        for tempDir in tempPaths(in: prefix) {
            guard fm.fileExists(atPath: tempDir.path) else { continue }
            let before = (try? size(of: tempDir)) ?? 0
            let entries = (try? fm.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            for entry in entries {
                try? fm.removeItem(at: entry)
            }
            let after = (try? size(of: tempDir)) ?? 0
            freed &+= max(0, before - after)
        }
        return freed
    }

    /// Human-readable byte count for UI display.
    static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
