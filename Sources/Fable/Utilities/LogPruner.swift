import Foundation

/// Keeps the logs directory from eating the disk. Wine debug output is
/// redirected per-launch to a log file; a misbehaving channel (e.g. the
/// msync wait-register flood) could balloon a single log to tens of GB, and
/// logs also accumulate across launches. This deletes runaway logs and trims
/// the directory to a budget, oldest first.
///
/// Skips anything modified in the last few minutes so it never yanks a log a
/// currently-running game is still writing to.
enum LogPruner {
    static func prune(
        directory: URL = AppPaths.logs,
        maxFileBytes: Int64 = 200 * 1_048_576,     // 200 MB: any single log past this is runaway
        maxTotalBytes: Int64 = 500 * 1_048_576,    // 500 MB: total budget across all logs
        activeWindow: TimeInterval = 300,          // don't touch logs written in the last 5 min
        now: Date = .now,
        fileManager fm: FileManager = .default
    ) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let items = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys)
        ) else { return }

        let cutoff = now.addingTimeInterval(-activeWindow)
        var files = items.compactMap { url -> (url: URL, size: Int64, date: Date)? in
            guard let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true else { return nil }
            let date = v.contentModificationDate ?? .distantPast
            guard date < cutoff else { return nil }  // skip active logs
            return (url, Int64(v.fileSize ?? 0), date)
        }

        // 1. Delete any single runaway log over the per-file cap.
        for file in files where file.size > maxFileBytes {
            try? fm.removeItem(at: file.url)
        }
        files.removeAll { $0.size > maxFileBytes }

        // 2. Trim the remaining total to budget, oldest first.
        var total = files.reduce(Int64(0)) { $0 + $1.size }
        guard total > maxTotalBytes else { return }
        for file in files.sorted(by: { $0.date < $1.date }) {
            if total <= maxTotalBytes { break }
            try? fm.removeItem(at: file.url)
            total -= file.size
        }
    }
}
