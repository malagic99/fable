import Foundation

/// Aggregate CPU% and resident memory for a process and its descendants.
/// Sampled by parsing `ps -ao pid,ppid,rss,pcpu` output — one shell-out
/// per poll, regardless of process-tree size.
struct ProcessMetrics: Hashable, Sendable {
    /// Resident set size in bytes.
    let residentBytes: Int64
    /// Aggregate CPU usage across the process tree. macOS reports
    /// per-core (so 200 means 2 fully-loaded cores); we don't normalize.
    let cpuPercent: Double

    static let zero = ProcessMetrics(residentBytes: 0, cpuPercent: 0)
}

enum ProcessMetricsError: Error {
    case psFailed(String)
}

enum ProcessMetricsSampler {
    /// One `ps` snapshot row.
    struct Snapshot: Hashable, Sendable {
        let pid: Int32
        let ppid: Int32
        /// Resident set size in KB (as ps reports it).
        let rssKB: Int64
        let cpuPercent: Double
    }

    /// Samples the full process list and aggregates everything reachable
    /// from `root` via the ppid graph (root itself included).
    static func sample(root: Int32) async throws -> ProcessMetrics {
        let snapshots = try await psSnapshot()
        return aggregate(snapshots, root: root)
    }

    nonisolated static func aggregate(_ snapshots: [Snapshot], root: Int32) -> ProcessMetrics {
        var byParent: [Int32: [Snapshot]] = [:]
        var byPID: [Int32: Snapshot] = [:]
        for snap in snapshots {
            byParent[snap.ppid, default: []].append(snap)
            byPID[snap.pid] = snap
        }

        var pending: [Int32] = [root]
        var visited: Set<Int32> = []
        var totalRssKB: Int64 = 0
        var totalCPU: Double = 0
        while let next = pending.popLast() {
            guard !visited.contains(next) else { continue }
            visited.insert(next)
            if let snap = byPID[next] {
                totalRssKB &+= snap.rssKB
                totalCPU += snap.cpuPercent
            }
            if let children = byParent[next] {
                pending.append(contentsOf: children.map(\.pid))
            }
        }

        return ProcessMetrics(
            residentBytes: totalRssKB * 1024,
            cpuPercent: totalCPU
        )
    }

    /// Parses `ps -ao pid,ppid,rss,pcpu` output. Skips the header line
    /// and any malformed rows (newer macOS adds " STAT" columns in some
    /// edge cases).
    nonisolated static func parse(_ output: String) -> [Snapshot] {
        var result: [Snapshot] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 4,
                  let pid = Int32(fields[0]),
                  let ppid = Int32(fields[1]),
                  let rss = Int64(fields[2]),
                  let cpu = Double(fields[3])
            else { continue }
            result.append(Snapshot(pid: pid, ppid: ppid, rssKB: rss, cpuPercent: cpu))
        }
        return result
    }

    // MARK: ps shell-out

    private static func psSnapshot() async throws -> [Snapshot] {
        let result = try await ProcessRunner.run(
            URL(filePath: "/bin/ps"),
            arguments: ["-axo", "pid=,ppid=,rss=,pcpu="]
        )
        guard result.succeeded else {
            throw ProcessMetricsError.psFailed(result.standardError)
        }
        return parse(result.standardOutput)
    }
}
