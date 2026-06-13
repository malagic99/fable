import Foundation
import Testing
@testable import Fable

@Suite struct ProcessMetricsTests {
    @Test
    func parsesPsRowsWithSpaceSeparation() {
        let output = """
          501     1 12345  1.5
          502   501  6789  0.0
          503   502   100  37.4
        """
        let snapshots = ProcessMetricsSampler.parse(output)
        #expect(snapshots.count == 3)
        #expect(snapshots[0].pid == 501)
        #expect(snapshots[1].ppid == 501)
        #expect(snapshots[2].rssKB == 100)
        #expect(snapshots[2].cpuPercent == 37.4)
    }

    @Test
    func skipsMalformedRows() {
        let output = """
          501     1 12345  1.5
          banana
          503   502   100
        """
        let snapshots = ProcessMetricsSampler.parse(output)
        #expect(snapshots.count == 1)
    }

    @Test
    func aggregateWalksProcessTreeAndSumsMemory() {
        let snapshots: [ProcessMetricsSampler.Snapshot] = [
            .init(pid: 100, ppid: 1, rssKB: 1024, cpuPercent: 5.0),
            .init(pid: 200, ppid: 100, rssKB: 2048, cpuPercent: 10.0),
            .init(pid: 300, ppid: 200, rssKB: 4096, cpuPercent: 20.0),
            // Sibling of 100 — must NOT be counted.
            .init(pid: 999, ppid: 1, rssKB: 8192, cpuPercent: 50.0),
        ]
        let metrics = ProcessMetricsSampler.aggregate(snapshots, root: 100)
        #expect(metrics.residentBytes == (1024 + 2048 + 4096) * 1024)
        #expect(metrics.cpuPercent == 35.0)
    }

    @Test
    func aggregateOnUnknownRootIsZero() {
        let metrics = ProcessMetricsSampler.aggregate([], root: 42)
        #expect(metrics == .zero)
    }

    @Test
    func aggregateHandlesCyclesWithoutInfiniteLoop() {
        // ps would never report this, but the walker must be defensive.
        let cyclic: [ProcessMetricsSampler.Snapshot] = [
            .init(pid: 1, ppid: 2, rssKB: 100, cpuPercent: 1),
            .init(pid: 2, ppid: 1, rssKB: 200, cpuPercent: 2),
        ]
        let metrics = ProcessMetricsSampler.aggregate(cyclic, root: 1)
        #expect(metrics.residentBytes == 300 * 1024)
    }
}
