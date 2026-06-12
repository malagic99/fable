import Foundation

/// File-by-file recursive copy with byte-level progress — FileManager's
/// copyItem can't report progress. Cancellable via task cancellation.
enum DirectoryCopier {
    /// If `source` is a directory, replicates its contents under
    /// `destination`. If it's a file, copies it to destination/<filename>.
    static func copy(
        _ source: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let files = try collectFiles(at: source)
            let totalBytes = max(files.reduce(0) { $0 + $1.size }, 1)

            try fm.createDirectory(at: destination, withIntermediateDirectories: true)

            var copied: Int64 = 0
            for file in files {
                try Task.checkCancellation()
                let target = destination.appending(path: file.relativePath)
                try fm.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fm.copyItem(at: file.url, to: target)
                copied += file.size
                progress(Double(copied) / Double(totalBytes))
            }
        }.value
    }

    private struct FileEntry {
        let url: URL
        let relativePath: String
        let size: Int64
    }

    private static func collectFiles(at source: URL) throws -> [FileEntry] {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw CocoaError(.fileNoSuchFile)
        }

        func size(of url: URL) -> Int64 {
            Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }

        guard isDirectory.boolValue else {
            return [FileEntry(url: source, relativePath: source.lastPathComponent, size: size(of: source))]
        }

        var entries: [FileEntry] = []
        let basePath = source.standardizedFileURL.path + "/"
        if let enumerator = fm.enumerator(
            at: source,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ) {
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values?.isRegularFile == true else { continue }
                let relative = String(url.standardizedFileURL.path.dropFirst(basePath.count))
                entries.append(FileEntry(url: url, relativePath: relative, size: Int64(values?.fileSize ?? 0)))
            }
        }
        return entries
    }
}
